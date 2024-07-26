local letters = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}
local userCooldowns = {}
local currentQuestion
local questionAnsweredBy
local queryRunning = false
local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
local mode = "query"
local answeredCorrectly = {}
local submittedAnswer = {}
local awaitingAnswer = false
local questionPoints = 1
local timeSinceLastMessage = tick()
local placeId = game.PlaceId
local replicatedStorage = game:GetService("ReplicatedStorage")
local textChatService = game:GetService("TextChatService")
local queryCooldown = false
local answerOptionsSaid = 0 -- how many answer options have been said (0 = none, 1 = a, 2 = b, etc.). Prevents users from spamming letters before they even know what the corresponding answer option is
local minMessageCooldown = 1.8 -- how much you need to wait to send another message to avoid ratelimit

local settings = {
    questionTimeout = 13,
    userCooldown = 3,
    sendLeaderBoardAfterQuestions = 3,
    automaticLeaderboards = true,
    automaticServerQueryLeaderboard = true,
    signStatus = true,
    romanNumbers = true,
    autoplay = false,
    repeatTagged = true
}

local numberMap = {
    {1000, 'M'},
    {900, 'CM'},
    {500, 'D'},
    {400, 'CD'},
    {100, 'C'},
    {90, 'XC'},
    {50, 'L'},
    {40, 'XL'},
    {10, 'X'},
    {9, 'IX'},
    {5, 'V'},
    {4, 'IV'},
    {1, 'I'}
}

function intToRoman(num)
    local roman = ""
    while num > 0 do
        for _, v in pairs(numberMap)do
            local romanChar = v[2]
            local int = v[1]
            while num >= int do
                roman = roman..romanChar
                num = num - int
            end
        end
    end
    return roman
end

local oldChat: boolean
if replicatedStorage:FindFirstChild('DefaultChatSystemChatEvents') then
    oldChat = true
else
    oldChat = false
end

local function Chat(msg)
    if replicatedStorage:FindFirstChild('DefaultChatSystemChatEvents') then
        replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
    else
        textChatService.TextChannels.RBXGeneral:SendAsync(msg)
    end
end

local function Shuffle(tbl) -- Table shuffle function by sleitnick
    local rng = Random.new()
    for i = #tbl, 2, -1 do
        local j = rng:NextInteger(1, i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

function roundNumber(num, numDecimalPlaces)
    return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end

local antiFilteringDone: boolean
local importantMessageSent: boolean -- if a important message that needs to be resent if filtered has been sent recently
local messageBeforeFilter: string
local answeredByAltMessage: string -- alt message specially for the correct answer text
function SendMessageWhenReady(message: string, important: boolean?, altMessage: string?) -- sends message so roblox won't rate limit it. if message is "important", script will send it again if it gets filtered/tagged first time. Altmessage is the message to send instead of original if it gets tagged
    if not queryRunning then
        return
    end
    if not settings.repeatTagged then
        important = false
    end
    if important then
        importantMessageSent = true
        messageBeforeFilter = message
        answeredByAltMessage = altMessage
        antiFilteringDone = false
    end
    if tick() - timeSinceLastMessage >= minMessageCooldown then
        Chat(message)
        timeSinceLastMessage = tick()
    else
        task.wait(minMessageCooldown - (tick() - timeSinceLastMessage))
        if not queryRunning then
            return
        end
        Chat(message)
        timeSinceLastMessage = tick()
    end
    if important then
        while not antiFilteringDone and queryRunning do -- yields until the anti filter functions have done their job
            task.wait()
        end
    end
    importantMessageSent = false
end

local boothGame = false
local signRemote
local changeSignTextRemote
if placeId == 8351248417 then
    signRemote = replicatedStorage:WaitForChild("Remotes"):WaitForChild("SettingsRem")
    changeSignTextRemote = replicatedStorage.SharedModules.TextInputPrompt.TextInputEvent
    if signRemote and changeSignTextRemote then
        boothGame = true
    end
end
local function UpdateSignText(text: string)
    if not boothGame or not settings.signStatus or not text then -- only works in "booth game"
        return
    end
    local sign = localPlayer.Character:FindFirstChild("TextSign") or localPlayer.Backpack:FindFirstChild("TextSign")
    if not sign then
        return
    end
    signRemote:FireServer({"SignServer"})
    changeSignTextRemote:FireServer(text)
end

local maxCharactersInMessage = 200
if placeId == 5118029260 then -- GRP cuts down messages at 100 characters
    maxCharactersInMessage = 100
end

local endMessage = "Queries ended"
if localPlayer.UserId == 2005147350 then
    endMessage = "Queries ended"
end

local function CalculateReadTime(text: string): number
    local timeToWait = #string.split(text, " ") * 0.4
    if timeToWait < minMessageCooldown then
        timeToWait = minMessageCooldown
    end
    return timeToWait
end
-------

--- Question OOP ---
local question = {}
question.__index = question

function question.New(quesitonText: string, options: table, value: number, correctAnswer: number)
    local newQuestion = {}
    newQuestion.mainQuestion = quesitonText
    newQuestion.answers = options
    if not correctAnswer then
        correctAnswer = 1
    end
    newQuestion.rightAnswer = letters[correctAnswer]
    newQuestion.rightAnswerIndex = correctAnswer
    if not value then
        newQuestion.value = 1
    else
        newQuestion.value = value
    end
    setmetatable(newQuestion, question)
    return newQuestion
end

function question:Ask()
    if not queryRunning then
        return
    end
    answerOptionsSaid = 0
    local rightAnswerBeforeShuffle = self.answers[self.rightAnswerIndex]
    self.answers = Shuffle(self.answers)
    self.rightAnswerIndex = table.find(self.answers, rightAnswerBeforeShuffle)
    self.rightAnswer = letters[self.rightAnswerIndex]
    if self.value > 1 then
        SendMessageWhenReady("💸 - "..self.value.."x points for question")
        task.wait(2)
    end
    questionAnsweredBy = nil
    UpdateSignText(self.mainQuestion)
    currentQuestion = self
    questionPoints = self.value
    SendMessageWhenReady("🗣 - "..self.mainQuestion, true)
    if not queryRunning then
        return
    end
    task.wait(CalculateReadTime(self.mainQuestion))
    for i, v in ipairs(self.answers) do
        if questionAnsweredBy or not queryRunning then
            return
        end
        if i ~= 1 then
            task.wait(CalculateReadTime(v))
        end
        if questionAnsweredBy or not queryRunning then
            return
        end
        SendMessageWhenReady(letters[i]..") "..v, true) -- 1 = A) 2 = B) 3 = C) etc.
        answerOptionsSaid = i
    end
end

local function SplitIntoMessages(itemTable: table, separtor: string, waitTime: number?) -- split table into multiple messages to prevent roblox cutting down the message
    local tempItemList = {}
    local currentLength = 0
    for _, item in pairs(itemTable) do
        if queryRunning then
            return
        end
        if currentLength + #item + (#separtor * #tempItemList) >= maxCharactersInMessage then -- maxCharactersInMessage characters is the limit for chat messages in Roblox. For each item, we are adding a sepatator
            local conctatTable = table.concat(tempItemList, separtor)
            Chat(conctatTable)
            task.wait(waitTime or CalculateReadTime(conctatTable) * 0.6) -- multiplied by 0.6 because full read time is too long
            if queryRunning then
                return
            end
            table.clear(tempItemList)
            table.insert(tempItemList, item)
            currentLength = #item
        else
            table.insert(tempItemList, item)
            currentLength = currentLength + #item
        end
    end
    if not queryRunning then
        Chat(table.concat(tempItemList, separtor))
    end
end
--- Category OOP ---
local categoryManager = {}
local categories = {}
categoryManager.__index = categoryManager

function categoryManager.New(categoryName)
    categories[categoryName] = {}
    local newCategory = categories[categoryName]
    setmetatable(newCategory, categoryManager)
    return newCategory
end

function categoryManager:Add(quesitonText: string, options: table, value: number, correctAnswer: number)
    local newQuestion = question.New(quesitonText, options, value, correctAnswer)
    table.insert(self, newQuestion)
end

--- Points OOP ---
local pointManager = {}
local userPoints = {}
pointManager.__index = pointManager

function pointManager.NewAccount(player)
    userPoints[player.Name] = {}
    local playerPoints = userPoints[player.Name]
    playerPoints.GlobalPoints = 0
    playerPoints.CurrentQueryPoints = 0
    setmetatable(playerPoints, pointManager)
    return playerPoints
end

function pointManager.AddPoints(player, points: number, type: string)
    if not points or not tonumber(points) then
        points = 1
    end
    if not type then
        type = "All"
    end
    local playerAccount = userPoints[player.Name]
    if not playerAccount then
        playerAccount = pointManager.NewAccount(player)
    end
    if type == "All" then
        playerAccount.GlobalPoints += points
        if queryRunning then
            playerAccount.CurrentQueryPoints += points
        end
    elseif type == "Global" then
        playerAccount.GlobalPoints += points
    elseif type == "CurrentQuery" then
        playerAccount.CurrentQueryPoints += points
    end
end

function pointManager.ClearQueryPointsForPlayer(player)
    local playerAccount = userPoints[player.Name]
    if not playerAccount then
        return
    end
    playerAccount.CurrentQueryPoints = 0
end

function pointManager.ClearQueryPoints()
    for _, v in pairs(userPoints) do
        v.CurrentQueryPoints = 0
    end
end

function pointManager.ClearGlobalPointsForPlayer(player)
    local playerAccount = userPoints[player.Name]
    if not playerAccount then
        return
    end
    playerAccount.GlobalPoints = 0
end

function pointManager.ClearGlobalPoints()
    for _, v in pairs(userPoints) do
        v.GlobalPoints = 0
    end
end

function pointManager.RemoveAccount(player)
    if userPoints[player.Name] then
        userPoints[player.Name] = nil
    end
end

function pointManager.ResetAllPoints()
    for _, v in pairs(userPoints) do
        v.GlobalPoints = 0
        v.CurrentQueryPoints = 0
    end
end
-------

local function requestSendMessage(message)
    timeSinceLastMessage = tick() - timeSinceLastMessage
    if timeSinceLastMessage > 2.5 then
        Chat(message)
        timeSinceLastMessage = tick()
    end
end

local function startChatListening(message: string, player: Player)
    local messageContent = string.upper(message) or ""
    if not currentQuestion or questionAnsweredBy or table.find(userCooldowns, player.Name) or table.find(blockedPlayers, player.Name) or table.find(submittedAnswer, player.Name) or (#whiteListedplayers > 0 and not table.find(whiteListedplayers, player.Name)) then
        return
    end
    local matchAnswer
    local minLenght = 4
    if #currentQuestion.answers[currentQuestion.rightAnswerIndex] < minLenght then
        minLenght = #currentQuestion.answers[currentQuestion.rightAnswerIndex] -- if minlenght is higher the the lenght of the correct answer, decrease it
    end
    if #messageContent >= minLenght then
        for _, v in ipairs(currentQuestion.answers) do
            if v:upper() == messageContent then
                matchAnswer = v
                break
            elseif (string.match(v:upper(), messageContent) and #string.match(v:upper(), messageContent) >= minLenght) or string.match(messageContent, v:upper()) then
                if matchAnswer then -- no more than 1 match
                    return
                end
                matchAnswer = v
            end
        end
    end
    local matchingLetter = nil
    if not matchAnswer then -- check if single letter is specified. For example: "I think it is B"
        local senderCharacter = player.Character
        local character = localPlayer.Character
        if not senderCharacter or not character then
            return
        end

        local patterns = {}
        patterns[1] = "%s([A-"..letters[#currentQuestion.answers].."])%s" -- checks for letter surrounded by spaces on both sides (ex: "I think B is the right answer")
        patterns[2] = "%s([B-"..letters[#currentQuestion.answers].."])$" -- checks for letter with space before it at the end of the string (ex: "I think it is B"). A excluded to prevent false matches (ex: "It is *a* dog")
        patterns[3] = "^([A-"..letters[#currentQuestion.answers].."])%s" -- checks for letter with space after it at the beginning of the string (ex: "B I think")
        patterns[4] = "^([A-"..letters[#currentQuestion.answers].."])$" -- checks for letter with no spaces after or before it (ex: "B")

        messageContent = string.gsub(messageContent, "[%).?!]", "") -- removes ), ., ?, and ! to recognize people saying a), b., c?, or d!
        local magnitude = (character.HumanoidRootPart.Position - senderCharacter.HumanoidRootPart.Position).Magnitude -- make sure sender is not too far away to prevent false matches
        if magnitude < 10 then
            for i = 1, 4 do
                local match = messageContent:match(patterns[i])
                if match and table.find(letters, match) <= answerOptionsSaid then
                    if matchingLetter then -- if more than one match, return
                        return
                    end
                    matchingLetter = match
                end
            end
        else
            matchingLetter = messageContent:match(patterns[4])
            if matchingLetter then
                if table.find(letters, matchingLetter) > answerOptionsSaid then
                    matchingLetter = nil
                end
            end
        end
    end
    if matchingLetter or matchAnswer then
        if matchingLetter == currentQuestion.rightAnswer or matchAnswer == currentQuestion.answers[currentQuestion.rightAnswerIndex] then
            if mode == "query" then
                questionAnsweredBy = player
                currentQuestion = nil
            else
                table.insert(submittedAnswer, player.Name)
                table.insert(answeredCorrectly, player.DisplayName)
                if #answeredCorrectly == 1 then
                    pointManager.AddPoints(player, questionPoints * 1.5) -- person who answers first gets 1.5x points
                else
                    pointManager.AddPoints(player, questionPoints)
                end
            end
        elseif mode == "query" then
            if awaitingAnswer then
                requestSendMessage("😹✖ - "..player.DisplayName.." answered WRONG. Retry in "..tostring(settings.userCooldown).." seconds")
            end
            table.insert(userCooldowns, player.Name)
            task.delay(settings.userCooldown, function()
                table.remove(userCooldowns, table.find(userCooldowns, player.Name))
            end)
        elseif mode == "multiple" then
            table.insert(submittedAnswer, player.Name)
        end
    end
end

local filtersInARow = 0
local function processMessage(player: Player, message: string)
    if player ~= localPlayer then
        startChatListening(message, player)
    else
        if not importantMessageSent or not queryRunning then
            return
        end
        if messageBeforeFilter == message or (answeredByAltMessage and string.find(message, answeredByAltMessage)) then -- if message before and after filtering are exactly the same, the message has not been filtered
            filtersInARow = 0
            antiFilteringDone = true
            return
        elseif math.abs(#message - #messageBeforeFilter) > 5 then -- if the lenght is diffrent from messageBeforeFilter the message is unrelated. Also give some space for diffrence to account for roblox weirdness with filtered lengh being diffrent from original lenght
            return
        end
        filtersInARow += 1
        if filtersInARow == 1 then
            SendMessageWhenReady("🔄 - Attempting to resend filtered message...")
            task.wait(5) -- waiting makes the the filtering system less agressive
        elseif filtersInARow == 2 then
            SendMessageWhenReady("🔄 - Resending previous filtered message...")
            task.wait(6)
        else
            SendMessageWhenReady("🛠️ - Attempting to get around chat filter")
            task.wait(6)
            filtersInARow = 0
        end
        if not queryRunning then
            return
        end
        if questionAnsweredBy and answeredByAltMessage then -- proceed to say message after question asnwered only if the message is the message with the correct answer
            SendMessageWhenReady(answeredByAltMessage)
            antiFilteringDone = true
            return
        elseif questionAnsweredBy then
            antiFilteringDone = true
            return
        end
        SendMessageWhenReady(messageBeforeFilter)
        antiFilteringDone = true
    end
end


local chatConnection
local joinConnection
local playerChatConnections = {}
if oldChat then
    settings.repeatTagged = false -- repeating tagged messages does not work on old chat system because of problems with diffrent chat event (player.Chatted vs textChatService.MessageReceived)
    for _, player in players:GetPlayers() do
        if player ~= localPlayer then
            local connection
            connection = player.Chatted:Connect(function(message)
                startChatListening(message, player)
            end)
            table.insert(playerChatConnections, connection)
        end
    end
    joinConnection = players.PlayerAdded:Connect(function(player)
        local connection
        connection = player.Chatted:Connect(function(message)
            startChatListening(message, player)
        end)
        table.insert(playerChatConnections, connection)
    end)
else
    chatConnection = textChatService.MessageReceived:Connect(function(textChatMessage)
        local player = if textChatMessage.TextSource then players:GetPlayerByUserId(textChatMessage.TextSource.UserId) else nil
        if not player then
            return
        end
        local message = textChatMessage.Text
        processMessage(player, message)
    end)
end


local function awaitAnswer(targetQuestion)
    if not queryRunning then
        return
    end
    awaitingAnswer = true
    local timeIsOut = false
    local function Timeout()
        if not queryRunning then
            return
        end
        task.wait(settings.questionTimeout)
        UpdateSignText(targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex])
        SendMessageWhenReady("⏱ - Times up. The answer was: "..targetQuestion.rightAnswer..") "..targetQuestion.answers[targetQuestion.rightAnswerIndex], true)
        timeIsOut = true
        currentQuestion = nil
        questionAnsweredBy = nil
        awaitingAnswer = false
    end
    local function SignTime()
        for timeLeft = settings.questionTimeout, 1, -1 do
            if questionAnsweredBy then
                return
            end
            if settings.romanNumbers then
                UpdateSignText(tostring(intToRoman(timeLeft))) -- convert to roman number and then convert to string
            else
                UpdateSignText(tostring(timeLeft))
            end
            task.wait(1)
        end
    end
    local timeoutCoroutine = coroutine.create(Timeout)
    local signTimeCoroutine = coroutine.create(SignTime)
    coroutine.resume(timeoutCoroutine)
    if boothGame and settings.signStatus then
        coroutine.resume(signTimeCoroutine)
    end

    if mode == "query" then
        while questionAnsweredBy == nil and not timeIsOut and queryRunning do
            task.wait()
        end
        if timeIsOut or not queryRunning then
            return
        end
        coroutine.close(timeoutCoroutine)
        coroutine.close(signTimeCoroutine)
        pointManager.AddPoints(questionAnsweredBy, targetQuestion.value)
        task.delay(0.5, function() -- delayed to give time to the signtimecoroutine to stop chanong sign text
            UpdateSignText(targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex])
        end)
        SendMessageWhenReady("🙀✔ - "..questionAnsweredBy.DisplayName.." answered RIGHT!. Answer was: "..targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex], true, "Answer was: "..targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex])
        questionAnsweredBy = nil
        awaitingAnswer = false
        table.clear(userCooldowns)
    else
        while not timeIsOut and queryRunning do
            task.wait(1)
            questionPoints -= questionPoints / settings.questionTimeout
        end
        task.wait(2)
        if not queryRunning then
            return
        end
        if #answeredCorrectly > 0 then
            local tempuserList = {} -- split players into multiple messages to prevent roblox cutting down the message
            local currentLength = 37
            local firstIteration = true
            for _, user in pairs(answeredCorrectly) do
                if currentLength + #user + (2 * #tempuserList) >= maxCharactersInMessage then -- maxCharactersInMessage is the limit for chat messages in Roblox. For each user, we are adding 2 more characters (, )
                    if firstIteration then
                        SendMessageWhenReady("🎉 - Players who answered correctly: "..table.concat(tempuserList, ", "))
                        firstIteration = false
                    else
                        SendMessageWhenReady(table.concat(tempuserList, ", "))
                    end
                    task.wait(3)
                    table.clear(tempuserList)
                    table.insert(tempuserList, user)
                    currentLength = #user
                else
                    table.insert(tempuserList, user)
                    currentLength = currentLength + #user
                end
            end
            if #tempuserList > 0 then
                if firstIteration then
                    SendMessageWhenReady("🎉 - Players who answered correctly: "..table.concat(tempuserList, ", "))
                    firstIteration = false
                else
                    SendMessageWhenReady(table.concat(tempuserList, ", "))
                end
            end
        end
        table.clear(answeredCorrectly)
        table.clear(submittedAnswer)
        awaitingAnswer = false
        currentQuestion = nil
    end
end

--- Questions ---
local flagsEasy = categoryManager.New("Flags-easy")
flagsEasy:Add("What flag is this? 🇯🇵", {"Japan", "China", "South Korea", "Vietnam"})
flagsEasy:Add("What flag is this? 🇫🇷", {"France", "Italy", "Germany", "Spain"})
flagsEasy:Add("What flag is this? 🇦🇺", {"Australia", "New Zealand", "Fiji", "Papua New Guinea"}, 2)
flagsEasy:Add("What flag is this? 🇨🇦", {"Canada", "United States", "Mexico", "Brazil"})
flagsEasy:Add("What flag is this? 🇬🇧", {"United Kingdom", "Ireland", "Scotland", "Wales"})

local flagsEasy2 = categoryManager.New("Flags-easy2")
flagsEasy2:Add("What flag is this? 🇮🇹", {"Italy", "Spain", "Greece", "Portugal"}, 2)
flagsEasy2:Add("What flag is this? 🇧🇷", {"Brazil", "Argentina", "Chile", "Peru"})
flagsEasy2:Add("What flag is this? 🇨🇳", {"China", "Japan", "Beijing", "Vietnam"})
flagsEasy2:Add("What flag is this? 🇷🇺", {"Russia", "Germany", "Sweden", "Norway"})
flagsEasy2:Add("What flag is this? 🇿🇦", {"South Africa", "Kenya", "Nigeria", "Egypt"})

local flagsMedium = categoryManager.New("Flags-medium")
flagsMedium:Add("What flag is this? 🇮🇳", {"India", "Pakistan", "Bangladesh", "Sri Lanka"})
flagsMedium:Add("What flag is this? 🇵🇭", {"Philippines", "Indonesia", "Vietnam", "Thailand"})
flagsMedium:Add("What flag is this? 🇳🇱", {"Netherlands", "Belgium", "Luxembourg", "Denmark"}, 2)
flagsMedium:Add("What flag is this? 🇧🇧", {"Barbados", "Bahamas", "Belize", "Bermuda"})
flagsMedium:Add("What flag is this? 🇸🇪", {"Sweden", "Norway", "Finland", "Denmark"})

local flagsHard = categoryManager.New("Flags-hard")
flagsHard:Add("What flag is this? 🇩🇰", {"Denmark", "Dominican Republic", "Djibouti"})
flagsHard:Add("What flag is this? 🇪🇷", {"Eritrea", "Ecuador", "El Salvador"}, 2)
flagsHard:Add("What flag is this? 🇫🇮", {"Finland", "Sweden", "Falkland Islands"})
flagsHard:Add("What flag is this? 🇿🇲", {"Zambia", "Zimbabwe", "Zaire"})
flagsHard:Add("What flag is this? 🇰🇷", {"South Korea", "North Korea", "Vietnam"})

local science = categoryManager.New("Science")
science:Add("The standard unit of measurement used for measuring force is which of the following?", {"Newton", "Mile", "Watt", "Kilogram"})
science:Add("How long does it take the earth to do one full rotation of the sun?", {"365 days", "7 days", "30 days"})
science:Add("Oil, natural gas and coal are examples of …", {"Fossil fuels", "Renewable resources", "Biomass fuel", "Geocentric resources"}, 2)
science:Add("Why do our pupils constrict in bright light?", {"To let in less light", "To give our eyes more oxygen", "To change our vision to 3D"})
science:Add("What is cooling lava called?", {"Igneous rocks", "Magma", "Fossils"})

local science2 = categoryManager.New("Science2")
science2:Add("What is faster, sound or light?", {"Light", "Sound", "They travel at the same speed", "They don't move"})
science2:Add("What is the main cause of seasons on the Earth?", {"The tilt of the Earth's axis in relation to the sun", "The speed that the Earth rotates around the sun", "Changes in amount of energy coming from the sun", "The distance between the Earth and the sun"}, 2)
science2:Add("What is the smallest unit of matter?", {"Atom", "Molecule", "Cell", "Particle"})
science2:Add("Which of these is a major concern about the overuse of antibiotics?", {"The bacteria will become antibiotic-resitant", "There will be an antibiotic shortage", "Antibiotics can cause secondary infections", "Antibiotics will get into the water system"})
science2:Add("What is the powerhouse of the cell?", {"Mitochondria", "Nucleus", "Cytoplasm", "Nucleic membrane"})

local history = categoryManager.New("History")
history:Add("Which of these countries did the Soviet Union NEVER invade?", {"Sweden", "Afghanistan", "Finland", "Poland"})
history:Add("What was the main cause of the French Revolution in 1789?", {"The social and economic inequality of the Third Estate", "The invasion of Napoleon Bonaparte", "The assassination of King Louis XVI", "The spread of the Black Death"})
history:Add("Which of these historical events happened first?", {"The American Revolution", "The French Revolution", "The Industrial Revolution", "The Russian Revolution"}, 2)
history:Add("What ancient civilization built the Machu Picchu complex?", {"Inca", "Aztec", "Maya", "Egypt"})
history:Add("In what modern-day country was Karl Marx, the communist philosopher, born?", {"Germany", "France", "Russia", "China"})

local history2 = categoryManager.New("History2")
history2:Add("Which pandemic killed a third of Europe's population in the 14th century?", {"Plague (Black Death)", "Spanish Flu", "Smallpox", "Malaria"})
history2:Add("Who was the first President of the United States?", {"George Washington", "Thomas Jefferson", "John Adams", "James Madison"})
history2:Add("In which year did Christopher Columbus first voyage to the Americas?", {"1492", "1507", "1513", "1520"})
history2:Add("Which ancient civilization built the pyramids at Giza?", {"Ancient Egyptians", "Ancient Greeks", "Mesopotamians", "Romans"}, 2)
history2:Add("Who is known for leading the Salt March to protest British salt taxes in colonial India?", {"Mahatma Gandhi", "Jawaharlal Nehru", "Subhas Chandra Bose", "Indira Gandhi"})

local food = categoryManager.New("Food")
food:Add("Which spice is known as 'the queen of spices'?", {"Saffron", "Cinnamon", "Vanilla", "Paprika"}, 2)
food:Add("What is the main ingredient of the traditional Japanese dish, sushi?", {"Rice", "Noodles", "Seaweed", "Tofu"})
food:Add("What is the name of the traditional Japanese soup made with miso paste and dashi broth?", {"Miso soup", "Udon", "Ramen", "Soba"})
food:Add("Which fruit is known as 'the king of fruits'?", {"Durian", "Mango", "Pineapple", "Banana"})
food:Add("Which country is famous for producing Parmesan cheese?", {"Italy", "France", "Spain", "Switzerland"})

local mythology = categoryManager.New("Mythology")
mythology:Add("Who is the king of the Greek gods?", {"Zeus", "Poseidon", "Hades", "Apollo"})
mythology:Add("What creature is said to have the body of a lion, wings of an eagle, and the head of a human?", {"Griffin", "Centaur", "Sphinx", "Minotaur"})
mythology:Add("Which Norse god is known as the god of thunder?", {"Thor", "Loki", "Odin", "Freyja"})
mythology:Add("Who was the Greek goddess of wisdom and warfare?", {"Athena", "Artemis", "Hera", "Aphrodite"})
mythology:Add("What is the name of the Greek underworld ruled by Hades?", {"Tartarus", "Elysium", "Styx", "Hades"}, 2)

local trivia = categoryManager.New("Trivia")
trivia:Add("What is the national animal of Scotland?", {"Unicorn", "Red Deer", "Golden Eagle", "Scottish Wildcat"})
trivia:Add("What is the name of the scale that measures the intensity of hurricanes?", {"Saffir-Simpson Scale", "Fujita Scale", "Beaufort Scale", "Mercalli Scale"}, 2)
trivia:Add("What is the currency of South Africa?", {"Rand", "Peso", "Dinar", "Ruble"})
trivia:Add("Who discovered penicillin?", {"Alexander Fleming", "Louis Pasteur", "Robert Koch", "Joseph Lister"})
trivia:Add("In soccer, what does the term 'Hat-trick' refer to?", {"Scoring three goals in one game", "Scoring a goal with your head", "Assisting three goals in one game", "Scoring a goal in the last minute of the game"})

local guessTheLanguage = categoryManager.New("Guess the language")
guessTheLanguage:Add("Hola", {"Spanish", "Portuguese", "Italian", "French"}, 2)
guessTheLanguage:Add("안녕하세요", {"Korean", "Vietnamese", "Thai", "Tagalog"})
guessTheLanguage:Add("Ciao", {"Italian", "Greek", "Romanian", "Hungarian"})
guessTheLanguage:Add("مرحبا", {"Arabic", "Persian", "Urdu", "Turkish"})
guessTheLanguage:Add("Bonjour", {"French", "Swedish", "Danish", "Finnish"})

local capitals = categoryManager.New("Capitals")
capitals:Add("What is the capital city of France?", {"Paris", "London", "Rome", "Madrid"})
capitals:Add("What is the capital city of Brazil?", {"Brasília", "Rio de Janeiro", "São Paulo", "Salvador"})
capitals:Add("What is the capital city of South Africa?", {"Pretoria", "Cape Town", "Johannesburg", "Durban"}, 2)
capitals:Add("What is the capital city of Japan?", {"Tokyo", "Kyoto", "Osaka", "Nagoya"})
capitals:Add("What is the capital city of India?", {"New Delhi", "Mumbai", "Bangalore", "Kolkata"})

local capitalsHard = categoryManager.New("Capitals-hard")
capitalsHard:Add("What is the capital of Argentina?", {"Buenos Aires", "Santiago", "Lima"})
capitalsHard:Add("What is the capital of Algeria?", {"Algiers", "Casablanca", "Tunis"})
capitalsHard:Add("What is the capital city of Myanmar?", {"Naypyidaw", "Yangon", "Mandalay"})
capitalsHard:Add("What is the capital city of Slovakia?", {"Bratislava", "Budapest", "Prague"}, 2)
capitalsHard:Add("What is the capital city of Uganda?", {"Kampala", "Nairobi", "Lusaka"})

local geography = categoryManager.New("Geography")
geography:Add("Which river flows through Paris?", {"Seine", "Thames", "Danube", "Nile"})
geography:Add("In which country would you find the ancient city of Petra?", {"Jordan", "Egypt", "Lebanon", "Iraq"})
geography:Add("Which is the largest island in the Mediterranean Sea?", {"Sicily", "Cyprus", "Crete", "Malta"})
geography:Add("Which city is located at the confluence of the Rhône and Saône rivers?", {"Lyon", "Marseille", "Nice", "Bordeaux"}, 2)
geography:Add("What is the name of the mountain range that spans the border between France and Spain?", {"Pyrenees", "Alps", "Apennines", "Carpathians"})

local geographyMedium = categoryManager.New("Geography-medium")
geographyMedium:Add("Which river is the longest in the world?", {"The Nile", "Amazon River", "Yangtze River", "Yellow River"})
geographyMedium:Add("Which continent has the fewest countries?", {"Antarctica", "Australia", "South America", "Europe"})
geographyMedium:Add("Which one of the following countries is an archipelago?", {"Japan", "China", "India", "Brazil"})
geographyMedium:Add("What is the largest desert in the world?", {"Sahara Desert", "Arabian Desert", "Gobi Desert", "Kalahari Desert"})
geographyMedium:Add("Which ocean is the largest by area?", {"Pacific Ocean", "Atlantic Ocean", "Indian Ocean", "Southern Ocean"}, 2)

local geographyHard = categoryManager.New("Geography-hard")
geographyHard:Add("Which country has the largest land area?", {"Russia", "Canada", "China", "United States"})
geographyHard:Add("Which continent is home to the largest desert in the world?", {"Africa", "Asia", "Antarctica", "Australia"})
geographyHard:Add("Which one of the following countries is completely landlocked?", {"Bolivia", "Norway", "Japan", "New Zealand"}, 2)
geographyHard:Add("Which is the southernmost capital city in the world?", {"Wellington, New Zealand", "Buenos Aires, Argentina", "Canberra, Australia", "Montevideo, Uruguay"})
geographyHard:Add("Which lake is the largest by surface area in the world?", {"Lake Superior", "Lake Victoria", "Lake Baikal", "Great Bear Lake"})

local gaming = categoryManager.New("Gaming")
gaming:Add("What is the best-selling video game franchise of all time?", {"Mario", "Call of Duty", "Pokemon", "Grand Theft Auto"})
gaming:Add("Which video game introduced the character Sonic the Hedgehog?", {"Sonic the Hedgehog", "Super Mario Bros", "Pac-Man", "Donkey Kong"})
gaming:Add("What is the main objective in the game 'Minecraft'?", {"Survive and build structures", "Save the princess", "Race against time", "Complete quests"}, 2)
gaming:Add("Which game series features a protagonist named Kratos, who seeks revenge against the gods of Olympus?", {"God of War", "Assassin's Creed", "Final Fantasy", "The Witcher"})
gaming:Add("What is the name of the mythical land where most of the 'World of Warcraft' game takes place?", {"Azeroth", "Middle-earth", "Tamriel", "Gielinor"})

local gaming2 = categoryManager.New("Gaming2")
gaming2:Add("Which game series features a protagonist named Master Chief?", {"Halo", "Call of Duty", "Destiny", "Battlefield"}, 2)
gaming2:Add("Who is the creator of the game series Metal Gear Solid?", {"Hideo Kojima", "Shigeru Miyamoto", "Todd Howard", "Tim Schafer"})
gaming2:Add("Which game introduced the character Nathan Drake as the main protagonist?", {"Uncharted: Drake's Fortune", "The Last of Us", "Tomb Raider", "Assassin's Creed"})
gaming2:Add("What is the name of the virtual world where players build and explore environments using blocks?", {"Minecraft", "Roblox", "Fortnite", "Terraria"})
gaming2:Add("Which game is set in a post-apocalyptic Boston and follows the story of a parent searching for their child?", {"Fallout 4", "The Elder Scrolls V: Skyrim", "Borderlands 2", "Bioshock Infinite"})

local movies = categoryManager.New("Movies")
movies:Add("Who directed the movie 'Jurassic Park'?", {"Steven Spielberg", "George Lucas", "James Cameron", "Martin Scorsese"})
movies:Add("Which movie won the Academy Award for Best Picture in 2020?", {"Parasite", "1917", "Joker", "The Irishman"})
movies:Add("Which actor played the role of Tony Stark/Iron Man in the Marvel Cinematic Universe?", {"Robert Downey Jr.", "Chris Hemsworth", "Chris Evans", "Mark Ruffalo"})
movies:Add("What is the name of the fictional African country in the movie 'Black Panther'?", {"Wakanda", "Zamunda", "Genovia", "Latveria"}, 2)
movies:Add("Who directed the 1994 film 'The Shawshank Redemption'?", {"Frank Darabont", "Quentin Tarantino", "Christopher Nolan", "Martin Scorsese"})

local roblox = categoryManager.New("Roblox")
roblox:Add("What is the name of the virtual catalog where players can purchase accessories and items?", {"Roblox Catalog", "Roblox Store", "Roblox Shop", "Roblox Market"})
roblox:Add("Which event in Roblox is celebrated annually with exclusive items and games?", {"Bloxy Awards", "Roblox Summer Games", "Roblox Egg Hunt", "Roblox Winter Festival"})
roblox:Add("What is the name of the developer who created the game 'Jailbreak' on Roblox?", {"asimo3089 and badcc", "Nikilis", "Gusmanak", "Alexnewtron"}, 2)
roblox:Add("What is the primary currency used in Roblox for purchasing items and game passes?", {"Robux", "Tickets", "RoboCoins", "BloxBucks"})
roblox:Add("Which Roblox game holds the record for the most concurrent players, exceeding 10 million at its peak?", {"Adopt Me!", "MeepCity", "Royal High", "Tower of Hell"})

local roblox2 = categoryManager.New("Roblox2")
roblox2:Add("What is the name of the virtual currency used in Roblox?", {"Robux", "Tickets", "Credits", "Coins"})
roblox2:Add("Which Roblox event features an annual egg hunt across various games?", {"Roblox Summer Games", "Bloxy Awards", "Eggstravaganza", "Roblox Egg Hunt"}, 2)
roblox2:Add("Who is the CEO of Roblox?", {"David Baszucki", "Erik Cassel", "John Doe", "Builderman"})
roblox2:Add("Which developer platform is used to create games on Roblox?", {"Roblox Studio", "Roblox Builder", "Roblox Developer", "Roblox Creator"})
roblox2:Add("What is the name of the Roblox game where players build structures to survive disasters?", {"Natural Disaster Survival", "Survive The Disasters", "Disaster Island", "Disaster Simulator"})

local english = categoryManager.New("English")
english:Add("Which literary device uses exaggeration for emphasis or effect?", {"Hyperbole", "Metaphor", "Simile", "Irony"})
english:Add("What is the correct form of the verb in this sentence: 'She _____ her cat every morning'?", {"feeds", "feed", "feeding", "fed"})
english:Add("What type of sentence gives a command or makes a request?", {"Imperative", "Interrogative", "Declarative", "Exclamatory"})
english:Add("Which word is a synonym for 'abundant'?", {"Plentiful", "Scarce", "Sparse", "Limited"})
english:Add("What is the correct spelling of the word meaning 'a false or mistaken belief'?", {"Fallacy", "Falacy", "Falecy", "Phallacy"}, 2)

local animals = categoryManager.New("Animals")
animals:Add("What is the largest land animal?", {"Elephant", "Giraffe", "Whale", "Rhino"})
animals:Add("What is the name of a baby kangaroo?", {"Joey", "Cub", "Pup", "Kit"})
animals:Add("Capable of exceeding 186 miles per hour, what is the fastest creature in the animal kingdom?", {"Peregrine falcon", "Cheetah", "Horse", "Lion"})
animals:Add("What is the only mammal that can fly?", {"Bat", "Penguin", "Pterodactyl", "Dragon"}, 2)
animals:Add("Which of these “fish” is actually a fish?", {"Swordfish", "Starfish", "Crayfish", "Jellyfish"})

local sports = categoryManager.New("Sports")
sports:Add("Which sport involves throwing a heavy metal ball as far as possible?", {"Shot put", "Javelin throw", "Discus throw", "Hammer throw"})
sports:Add("What is the name of the annual championship game in American football?", {"Super Bowl", "World Series", "Stanley Cup Finals", "NBA Finals"})
sports:Add("Which athlete is known as 'The Greatest' and was a prominent boxer?", {"Muhammad Ali", "Mike Tyson", "Floyd Mayweather", "George Foreman"}, 2)
sports:Add("In which sport would you perform a 'slam dunk'?", {"Basketball", "Volleyball", "Tennis", "Golf"})
sports:Add("What is the name of the stadium that hosts the Wimbledon tennis tournament?", {"All England Club", "Centre Court", "Arthur Ashe Stadium", "Rod Laver Arena"})

local minecraft = categoryManager.New("Minecraft")
minecraft:Add("What is the name of the redstone device used for opening doors and activating mechanisms?", {"Lever", "Button", "Pressure Plate", "Redstone Torch"})
minecraft:Add("Which biome is characterized by tall, thin trees and mushrooms?", {"Swamp", "Taiga", "Mushroom Fields", "Jungle"}, 2)
minecraft:Add("What material is needed to craft a chest?", {"Wooden Planks", "Stone", "Iron Ingots", "Diamonds"})
minecraft:Add("What is the primary use of a brewing stand in Minecraft?", {"Brewing Potions", "Cooking Food", "Smelting Ores", "Enchanting Items"})
minecraft:Add("What type of block can only be obtained with a silk touch tool?", {"Glass", "Grass Block", "Ice", "Bookshelf"})

local chess = categoryManager.New("Chess")
chess:Add("What is the name of the piece that can only move diagonally?", {"Bishop", "Knight", "Queen"})
chess:Add("What is the term for a situation where a king is under attack and cannot escape?", {"Checkmate", "Stalemate", "En passant", "Castling"})
chess:Add("What is the name of the chess strategy that involves sacrificing a piece to gain an advantage?", {"Gambit", "Fork", "Pin", "Skewer"})
chess:Add("What is the name of the special move where a king and a rook swap places?", {"Castling", "Promotion", "Capture", "Fork"})
chess:Add("Which piece is involved in 'en passant'?", {"Pawn", "Queen", "Bishop", "Knight"}, 2)

local WWII = categoryManager.New("WWII")
WWII:Add("Which country was invaded by Germany, marking the beginning of World War II in Europe?", {"Poland", "France", "Norway", "Belgium"})
WWII:Add("What was the name of the German air force during WWII?", {"Luftwaffe", "Wehrmacht", "Kriegsmarine", "Schutzstaffel"})
WWII:Add("What was the codename for the Allied invasion of Normandy on June 6, 1944?", {"Operation Overlord", "Operation Torch", "Operation Market Garden", "Operation Barbarossa"}, 2)
WWII:Add("Which battle in 1942 marked a turning point for the Allies in the Pacific theater?", {"Battle of Midway", "Battle of Guadalcanal", "Battle of Iwo Jima", "Battle of Okinawa"})
WWII:Add("What was the code name for the German invasion of the Soviet Union in 1941?", {"Operation Barbarossa", "Operation Market Garden", "Operation Overlord", "Operation Bagration"})

local WWI = categoryManager.New("WWI")
WWI:Add("Which event led Austria-Hungary to declare war on Serbia in 1914?", {"Assassination of Archduke Franz Ferdinand", "Revolution in Sarajevo", "Blockade of Danube", "Treaty of Belgrade"})
WWI:Add("What was the name of the British passenger ship sunk by a German submarine in 1915, leading to significant outrage?", {"Lusitania", "Titanic", "Britannia", "Olympic"})
WWI:Add("What term describes the trench-based warfare that defined much of World War I?", {"Trench warfare", "Guerrilla warfare", "Dirt warfare", "Siege warfare"})
WWI:Add("Which battle in 1916 resulted in extensive casualties and is known for its ferocious fighting?", {"Battle of Verdun", "Battle of the Somme", "Battle of Ypres", "Battle of Tannenberg"})
WWI:Add("What was the name of the alliance between Germany, Austria-Hungary, and Italy during World War I?", {"The Central Powers", "The Axis Powers", "The Triple Entente", "The League of Nations"}, 2)

local luau = categoryManager.New("Luau")
luau:Add("Which keyword is used to define a variable in Luau?", {"local", "var", "let", "const"})
luau:Add("What is the operator used for exponentiation in Luau?", {"^", "**", "*", "//"})
luau:Add("What is the keyword used to break out of a loop in Luau?", {"break", "continue", "return", "exit"})
luau:Add("How do you check if a variable is nil in Luau?", {"if var == nil then", "if var is nil then", "if var equals nil then", "if var has nil"}, 2)
luau:Add("What function is used to print output in Luau?", {"print()", "write()", "output()", "console.log()"})

local astronomy = categoryManager.New("Astronomy")
astronomy:Add("Which planet is known as the 'Red Planet'?", {"Mars", "Jupiter", "Mercury", "Saturn"})
astronomy:Add("What is the name of the closest star to the Earth?", {"The Sun", "Proxima Centauri", "Sirius", "Alpha Centauri"})
astronomy:Add("What is the name of the phenomenon where a total solar eclipse forms a ring of light around the Moon?", {"Annular eclipse", "Partial eclipse", "Total eclipse", "Lunar eclipse"}, 2)
astronomy:Add("What is the name of the spacecraft that visited Pluto in 2015?", {"New Horizons", "Voyager 1", "Cassini", "Rosetta"})
astronomy:Add("What is the name of the galaxy that contains our solar system?", {"Milky Way", "Andromeda", "Triangulum", "Sombrero"})

local memes = categoryManager.New("Memes")
memes:Add("Which meme features a cat with a serious expression, known for its 'grumpy' appearance?", {"Grumpy Cat", "Doge", "Success Kid", "Bad Luck Brian"})
memes:Add("What is the name of the meme that involves a character drinking a beverage and making a disgusted face?", {"Disaster Girl", "Condescending Wonka", "Disappointed Guy", "Skeptical Baby"})
memes:Add("What is the term for a meme that involves an image with humorous text above and below it?", {"Image macro", "Reaction image", "Dank meme", "Wholesome meme"}, 2)
memes:Add("What is the name of the meme that features a woman yelling at a confused-looking cat sitting at a dinner table?", {"Woman Yelling at a Cat", "Table Cat", "Confused Dinner", "Dinner Argument"})
memes:Add("Which meme features a cartoon character walking away from an explosion, expressing nonchalance?", {"Epic Sax Guy", "Epic Win Guy", "Epic Fail Guy", "Epic Fail Man"})

local anarchy = categoryManager.New("Anarchy")
anarchy:Add("Who is considered the father of modern anarchism, known for his work 'What is Property?'", {"Pierre-Joseph Proudhon", "Mikhail Bakunin", "Peter Kropotkin", "Emma Goldman"}, 2)
anarchy:Add("What is the term for a society without rulers or government, often envisioned by anarchists?", {"Stateless society", "Communal society", "Utopian society", "Socialist society"})
anarchy:Add("Which anarchist thinker wrote the book 'The Ego and Its Own', advocating for self-interest and rejection of authority?", {"Max Stirner", "Benjamin Tucker", "Louise Michel", "Voltairine de Cleyre"})
anarchy:Add("Which symbol, often associated with anarchism, consists of an 'A' enclosed in a circle?", {"Circled A", "Red star", "Peace sign", "Lambda"})
anarchy:Add("Which anarchist movement emerged in Spain during the Spanish Civil War and focused on self-management and direct democracy?", {"Anarchist Catalonia", "Bolshevik Revolution", "Paris Commune", "Anarcho-Syndicalism"})

local anime = categoryManager.New("Anime")
anime:Add("In which anime series does the protagonist, Luffy, aim to become the Pirate King?", {"One Piece", "Naruto", "Bleach", "Dragon Ball"})
anime:Add("What is the name of the main protagonist in the popular anime and manga series 'Naruto'?", {"Naruto Uzumaki", "Sasuke Uchiha", "Kakashi Hatake", "Tsunade"})
anime:Add("What is the name of the virtual reality MMORPG in the anime 'Sword Art Online'?", {"Sword Art Online", "Gun Gale Online", "ALfheim Online", "Accel World"})
anime:Add("Which anime series features a group of students trying to assassinate their teacher, who has the appearance of an octopus?", {"Assassination Classroom", "Death Note", "Tokyo Ghoul", "Black Clover"}, 2)
anime:Add("What is the name of the protagonist in the anime 'Fullmetal Alchemist' who seeks the Philosopher's Stone?", {"Edward Elric", "Alphonse Elric", "Roy Mustang", "Winry Rockbell"})

local scienceHard = categoryManager.New("Science-hard")
scienceHard:Add("What is the name of the process by which plants convert light energy into chemical energy?", {"Photosynthesis", "Respiration", "Transpiration", "Fermentation"})
scienceHard:Add("What is the term for the force that opposes the relative motion or tendency of such motion between two surfaces in contact?", {"Friction", "Gravity", "Tension", "Velocity"})
scienceHard:Add("What is the name of the subatomic particle with no electric charge found in the nucleus of an atom?", {"Neutron", "Proton", "Electron", "Photon"}, 1)
scienceHard:Add("What is the name of the branch of biology that deals with the study of insects?", {"Entomology", "Herpetology", "Ornithology", "Ichthyology"}, 2)
scienceHard:Add("What is the name of the process by which a substance directly changes from a solid to a gas without passing through the liquid phase?", {"Sublimation", "Evaporation", "Condensation", "Fusion"})

local mathCategory = categoryManager.New("Math")
mathCategory:Add("What is the sum of the angles in a triangle?", {"180 degrees", "90 degrees", "360 degrees", "270 degrees"})
mathCategory:Add("What is the result of 3^4?", {"81", "27", "64", "12"})
mathCategory:Add("What is the formula for the circomference of a circle?", {"2 * π * r", "π * r^2", "2 * π * d", "π * r"}, 2)
mathCategory:Add("What is the name of the branch of mathematics that studies shapes and angles?", {"Geometry", "Algebra", "Calculus", "Arithmetic"})
mathCategory:Add("What is the value of x in the equation 2x + 5 = 13?", {"4", "3", "5", "6"})

local mathHard = categoryManager.New("Math-hard")
mathHard:Add("What is the name of the theorem that relates the sides and angles of a triangle, stating that (a/sin(A)) = (b/sin(B)) = (c/sin(C))?", {"Law of Sines", "Law of Cosines", "Pythagorean theorem", "Triangle Inequality Theorem"})
mathHard:Add("What is the derivative of ln(x)?", {"1/x", "x", "ln(x)", "e^x"})
mathHard:Add("What is the value of the square root of 64?", {"8", "6", "4", "10"})
mathHard:Add("What is the name of the sequence that starts with 1, 4, 9, 16, 25, ...?", {"Square Numbers", "Fibonacci Sequence", "Prime Numbers", "Cube Numbers"})
mathHard:Add("What is the name of the branch of mathematics that deals with the study of continuous change and motion?", {"Calculus", "Algebra", "Geometry", "Number Theory"}, 2)

local coldWar = categoryManager.New("Cold War")
coldWar:Add("Who was the Soviet leader during the Cuban Missile Crisis in 1962?", {"Nikita Khrushchev", "Leonid Brezhnev", "Mikhail Gorbachev", "Joseph Stalin"})
coldWar:Add("Which U.S. president signed the Intermediate-Range Nuclear Forces Treaty with the Soviet Union in 1987?", {"Ronald Reagan", "George H. W. Bush", "Jimmy Carter", "Bill Clinton"}, 2)
coldWar:Add("What was the name of the Soviet military alliance that opposed NATO during the Cold War?", {"Warsaw Pact", "Comecon", "Council for Mutual Economic Assistance", "Eastern Bloc"})
coldWar:Add("Which city became a symbol of Cold War division with a wall separating its eastern and western sectors?", {"Berlin", "Moscow", "Vienna", "Prague"})
coldWar:Add("Who was the first woman in space, launched by the Soviet Union during the Cold War?", {"Valentina Tereshkova", "Sally Ride", "Yuri Gagarin", "Judith Resnik"})

local chemistry = categoryManager.New("Chemistry")
chemistry:Add("What is the chemical symbol for gold?", {"Au", "Ag", "Pb", "Fe"})
chemistry:Add("What is the pH level of a neutral solution?", {"7", "0", "14", "5"})
chemistry:Add("Which gas is most abundant in Earth's atmosphere?", {"Nitrogen", "Oxygen", "Carbon Dioxide", "Helium"})
chemistry:Add("What is the name of the process where a gas turns into a liquid?", {"Condensation", "Evaporation", "Sublimation", "Freezing"})
chemistry:Add("What type of bond is formed when electrons are shared between atoms?", {"Covalent Bond", "Ionic Bond", "Hydrogen Bond", "Metallic Bond"}, 2)

local biology = categoryManager.New("Biology")
biology:Add("What is the name of the process by which plants convert light energy into chemical energy?", {"Photosynthesis", "Respiration", "Transpiration", "Fermentation"})
biology:Add("Which organelle is responsible for protein synthesis in cells?", {"Ribosome", "Mitochondria", "Nucleus", "Endoplasmic Reticulum"}, 2)
biology:Add("What is the term for the protective outer covering of a plant cell?", {"Cell Wall", "Cell Membrane", "Cytoplasm", "Nucleus"})
biology:Add("Which blood cells are responsible for oxygen transport in the body?", {"Red Blood Cells", "White Blood Cells", "Platelets", "Plasma"})
biology:Add("What is the process by which cells replicate their DNA and divide into two daughter cells?", {"Mitosis", "Meiosis", "Fertilization", "Transcription"})

local skibidiToilet = categoryManager.New("Skibidi toilet")
skibidiToilet:Add("What is the name of the biggest cameraman?", {"Titan cameraman", "Titan speakerman", "Large cameraman", "G-man"})
skibidiToilet:Add("Which race has the ability to teleport?", {"Tv race", "Camera race", "Speaker race", "Skibidi toilets"})
skibidiToilet:Add("What is the biggest skibidi toilet?", {"G-man", "Giant skibidi toilet", "King toilet", "Toilet lord"})
skibidiToilet:Add("When did Titan tvman appear?", {"Episode 41", "Episode 8", "Episode 26", "Episode 37"}, 2)
skibidiToilet:Add("What is the name of the first female in skibidi toilet?", {"Camerawoman", "Tvwoman", "Speakerwoman", "Upgraded camerawoman"})

local brainRot = categoryManager.New("BrainRot")
brainRot:Add("Who did baby gronk rizz?", {"Livvy dunne", "Ice spice", "Megan fox", "Skibidi"})
brainRot:Add("Who said the erm what the sigma line?", {"Squidward", "Kai cenat", "Caseoh", "Fanum"})
brainRot:Add("Fill in the blank: skibidi dop dop dop ___ ___ ___", {"yes yes yes", "no no no", "sigma rizz party", "alpha fanum tax"})
brainRot:Add("Who keeps taxing kai?", {"Fanum", "Speed", "Ray", "Duke"})
brainRot:Add("What is it called when you keep your mouth shut with proper tounge posture?", {"Mewing", "Edging", "Gooning", "Meowing"}, 2)

local brainRot2 = categoryManager.New("BrainRot2")
brainRot2:Add("What did the red larva say?", {"OI OI OI", "HEY HEY HEY", "OAI OAI OAI", "AY AY AY"})
brainRot2:Add("What are the materials little john used?", {"Galvanized square steel, Eco friendly wood veneers, aunt's screws", "Regular square steel, Regular wood veneers, Regular screws", "Steel, Wood, Screws", "Premium steel, Premium wood veneers, Premium screws"}, 2)
brainRot2:Add("Fill in the blank: erm what the ___", {"sigma", "skibidi", "alpha", "fanum"})
brainRot2:Add("What is it called when someone is giving extreme compliments to you?", {"Glazing", "Rizz", "Flirt", "Sigma"})
brainRot2:Add("What is the ultimate rizzer of all time called?", {"The rizzler", "The skibidi", "Little john", "Kai cenat"})

local physics = categoryManager.New("Physics")
physics:Add("What is the unit of electrical resistance?", {"Ohm", "Volt", "Ampere", "Watt"})
physics:Add("What is the speed of light in a vacuum?", {"300,000 kilometers/s", "30,000 kilometers/s", "3,000 kilometers/s", "3,000,000 kilometers/s"})
physics:Add("Which fundamental force is responsible for holding the nucleus of an atom together?", {"Strong Nuclear Force", "Gravitational Force", "Electromagnetic Force", "Weak Nuclear Force"}, 2)
physics:Add("Which law states that for every action, there is an equal and opposite reaction?", {"Newton's Third Law", "Newton's First Law", "Newton's Second Law", "Coulomb's Law"})
physics:Add("What is the primary force that causes the tides on Earth?", {"Gravitational force of the moon", "Gravitational force of the sun", "Magnetic force of the earth", "Wind force of the oceans"})

local music = categoryManager.New("Music")
music:Add("Which musical symbol indicates to play a note longer than its usual duration?", {"Fermata", "Accidental", "Tenuto", "Staccato"})
music:Add("Which instrument has keys, pedals, and strings?", {"Piano", "Guitar", "Violin", "Flute"})
music:Add("Which term is used to describe the speed of the beat in a piece of music?", {"Tempo", "Dynamics", "Pitch", "Harmony"})
music:Add("Which musical notation indicates the end of a piece?", {"Double Bar Line", "Repeat Sign", "Time Signature", "Coda"}, 2)
music:Add("Which musical term indicates a gradual increase in loudness?", {"Crescendo", "Diminuendo", "Staccato", "Legato"})

local geographyExtreme = categoryManager.New("Geography-extreme")
geographyExtreme:Add("What country in Asia is located in the northwest?", {"Turkey", "Kazakhstan", "Pakistan", "Georgia"})
geographyExtreme:Add("What country in Asia is located in the southwest?", {"India", "Nepal", "Yemen", "Oman"})
geographyExtreme:Add("What country in Asia is located in the south?", {"Sri Lanka", "Myanmar", "Malaysia", "Indonesia"}, 2)
geographyExtreme:Add("What country in Asia is located in the north?", {"Russia", "China", "Mongolia", "North Korea"})
geographyExtreme:Add("What country in Asia is located in the east?", {"Japan", "Philippines", "South Korea", "Taiwan"})

local pokemon = categoryManager.New("Pokemon")  
pokemon:Add("What is the starting Pokémon of the Kanto region?", {"Bulbasaur", "Charmander", "Squirtle", "Pikachu"})  
pokemon:Add("Which Pokémon is known for its ability to evolve into many different species?", {"Eevee", "Pikachu", "Charizard", "Squirtle"})  
pokemon:Add("What is the name of the Pokémon that is said to have the power of a hundred moves?", {"Mew", "Mewtwo", "Articuno", "Zapdos"})  
pokemon:Add("Which Pokémon is known for its incredible speed and is often considered the fastest Pokémon?", {"Deoxys", "Giratina", "Darkrai", "Arceus"}, 2)  
pokemon:Add("What is the name of the Pokémon that is said to have the power to control time?", {"Dialga", "Palkia", "Giratina", "Xerneas"})  

local spongebob = categoryManager.New("SpongeBob") 
spongebob:Add("What is the name of the main character in the animated TV series 'SpongeBob SquarePants'?", {"SpongeBob SquarePants", "Patrick Star", "Squidward Tentacles", "Sandy Cheeks"}) 
spongebob:Add("What is the name of SpongeBob's pet snail?", {"Gary", "Patrick", "Squidward", "Mr. Krabs"}) 
spongebob:Add("What is the name of the restaurant where SpongeBob works?", {"Krusty Krab", "Chum Bucket", "Bikini Bottom", "Jellyfish Fields"}) 
spongebob:Add("Who is SpongeBob's best friend?", {"Patrick Star", "Squidward Tentacles", "Sandy Cheeks", "Mr. Krabs"}, 2) 
spongebob:Add("What is the name of the city where SpongeBob lives?", {"Bikini Bottom", "Krusty Krab", "Jellyfish Fields", "Rock Bottom"})

local categoryTable = {}
for k, v in pairs(categories) do
    table.insert(categoryTable, k)
end
table.sort(categoryTable)

local function sendCategories()
    if not queryRunning then
        Chat("❓ - Trivia/multiple categories:")
        task.wait(3)
        SplitIntoMessages(categoryTable, ", ", 5)
    end
end

local function getDisplayNameByUsername(username)
    local displayName = players:FindFirstChild(username).DisplayName
    return displayName
end

local function sortUserPoints(type)
    local array = {}
    for key, value in pairs(userPoints) do
        array[#array+1] = {key, value[type]}
    end
    table.sort(array, function(a, b)
        return a[2] > b[2]
    end)
    return array
end

local function sendLeaderboard(type, message)
    local array
    if not message then
        message = ""
    end
    if type == "Current query" then
        array = sortUserPoints("CurrentQueryPoints")
    else
        array = sortUserPoints("GlobalPoints")
    end
    task.wait(1.5)
    if array[1] and array[1][2] > 0 then
        Chat(message..type.." Skibidi Sigmas 🏆")
        local username = array[1][1]
        local displayName = getDisplayNameByUsername(username)
        local points = tostring(roundNumber(array[1][2], 1))
        task.wait(2.5)
        Chat("👑🥇 "..displayName.." - "..points.." points")
        UpdateSignText("👑🥇 "..displayName)
        if array[2] and array[2][2] > 0 then
            username = array[2][1]
            displayName = getDisplayNameByUsername(username)
            points = tostring(roundNumber(array[2][2], 1))
            task.wait(2.5)
            Chat("🎆🥈 "..displayName.." - "..points.." points")
            UpdateSignText("🎆🥈 "..displayName)
            if array[3] and array[3][2] > 0 then
                task.wait(2.5)
                username = array[3][1]
                displayName = getDisplayNameByUsername(username)
                points = tostring(roundNumber(array[3][2], 1))
                Chat("🎉🥉 "..displayName.." - "..points.." points")
                UpdateSignText("🎉🥉 "..displayName)
                task.wait(2.5)
            end
        end
    end
end

local autoplayChosenCategories = {} -- categories previously chosen by autoplay
local function choseAutoplayCategory()
    local chosenCategory = categoryTable[math.random(#categoryTable)]
    if table.find(autoplayChosenCategories, chosenCategory) then -- if category has been previously chosen, chose another category
        return choseAutoplayCategory()
    else
        return chosenCategory
    end
end

local function startQuery(category)
    if queryRunning or queryCooldown then
        return
    end
    queryRunning = true
    pointManager.ClearQueryPoints()
    Chat('🎮 - "'..category..'" query has been chosen. Initiating queries...')
    UpdateSignText(category)
    task.wait(3)
    local loopIterations = 0
    for _, v in pairs(categories[category]) do
        if not queryRunning then
            return
        end
        v:Ask()
        awaitAnswer(v)
        if not queryRunning then
            return
        end
        task.wait(6)
        loopIterations += 1
        if not queryRunning then
            return
        end
        if loopIterations == settings.sendLeaderBoardAfterQuestions and settings.automaticLeaderboards and settings.automaticCurrentQueryLeaderboard then
            sendLeaderboard("Current query", "📜 ")
            loopIterations = 0
        end
    end
    task.wait(3)
    if loopIterations ~= 0 and settings.automaticLeaderboards and settings.automaticCurrentQueryLeaderboard then
        sendLeaderboard("Current query", "📜 ")
    end
    UpdateSignText(endMessage)
    task.delay(15, function()
       UpdateSignText("")
    end)
    if settings.automaticLeaderboards and settings.automaticServerQueryLeaderboard then
        sendLeaderboard("Server", "🏆 Questions ended. ")
        task.wait(2)
    else
        SendMessageWhenReady("🏁 | Questions ended")
        task.wait(3)
    end
    UpdateSignText(endMessage)
    queryRunning = false
    if settings.autoplay then
        table.insert(autoplayChosenCategories, category)
        Chat("🎲💭 - Picking next category...")
        local chosenCategory = choseAutoplayCategory()
        if #autoplayChosenCategories == #categoryTable then -- if every category has been chosen, clear the chosencategories table
            table.clear(autoplayChosenCategories)
        end
        task.wait(5)
        startQuery(chosenCategory)
    end
end

local queryModeRules = {"There is only one winner for each questions.", "If you answer correctly, you will earn one point (or two points if the question is a double point question).", "If you answer incorrectly, you will have to wait "..tostring(settings.userCooldown).." seconds before you can submit another answer."}
local multipleModeRules = {"There are multiple winners for each question.", "You can only submit ONE answer per round.", "The first answer you submit is your final answer, and it can not be changed.", "You have "..tostring(settings.questionTimeout).." seconds to answer the question after all the options have been said.", "Every second after all the options have been said, the points you will gain for answering correctly decrease.", "In other words, the quicker you answer, the more points you will gain.", "Additionally, the first person who submits a correct answer gets 1.5x points."}
local function sendRules()
    if mode == "query" then
        Chat("📢 | Query mode rules:")
        task.wait(2)
        SplitIntoMessages(queryModeRules, " ")
    elseif mode == "multiple" then
        Chat("📢 | Multiple mode rules:")
        task.wait(2)
        SplitIntoMessages(multipleModeRules, " ")
    end
end

game:GetService("Players").PlayerRemoving:Connect(function(player) -- remove player's userpoint account on leave
    pointManager.RemoveAccount(player)
end)

local function getPlayerByPlayerName(name)
    if name then
        name = name:lower()
        for i, v in ipairs(players:GetPlayers()) do
            if string.lower(string.sub(v.Name, 1, #name)) == name then
                return v
            end
            if string.lower(string.sub(v.DisplayName, 1, #name)) == name then
                return v
            end
        end
        for i, v in ipairs(players:GetPlayers()) do
            if string.match(v.Name:lower(), name) then
                return v
            end
            if string.match(v.DisplayName:lower(), name) then
                return v
            end
        end
    end
end

local function getTargetPlayer(name) -- try to get a target player from the name
    local target
    if name == " " or name == "" then
        -- if target player isn't specified, use the localplayer
        target = localPlayer
        return target
    end
    local matchingPlayer = getPlayerByPlayerName(name)
    if name:lower() == "me" then
        target = localPlayer
        return target
    elseif name:lower() == "random" then
        local playerTable = players:GetPlayers()
        target = playerTable[math.random(#playerTable)]
        return target
    elseif matchingPlayer then
        target = matchingPlayer
        return target
    end
    target = nil
    return target
end

local function getCategoryName(name) -- detects category from begging of string, for example: "gene" will return "general" category
    name = name:lower()
    for _, category in ipairs(categoryTable) do
        if string.lower(string.sub(category, 1, #name)) == name then
            return category
        end
    end
end
---------- UI ----------
local DiscordLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/UI-Libs/main/discord%20lib.txt"))()

-- Create the main window
local win = DiscordLib:Window("Goofy ahh script")

-- Create a server tab
local serv = win:Server("Main", "http://www.roblox.com/asset/?id=6031075938")

-- Main Controls Channel
local btns = serv:Channel("Main Controls")

-- Define the main UI functions
local function getTargetPlayer(value)
    if value:lower() == "all" then
        return "ALL"
    end
    for _, player in ipairs(game.Players:GetPlayers()) do
        if player.Name:lower():sub(1, #value) == value:lower() or player.DisplayName:lower():sub(1, #value) == value:lower() then
            return player
        end
    end
    return nil
end

btns:Button("Start query", function()
    if categories[selectedCategory] then
        startQuery(selectedCategory)
    end
end)

btns:Button("Stop", function()
    queryCooldown, queryRunning, currentQuestion, questionAnsweredBy, awaitingAnswer = true, false, nil, nil, false
    Chat("🛑 - Query Stopped.")
    task.delay(5, function() queryCooldown = false end)
end)

btns:Button("Send rules", function()
    sendRules()
end)

btns:Button("Send server LB", function()
    sendLeaderboard("Server", "🏆 ")
end)

btns:Button("Reset all points", function()
    pointManager.ResetAllPoints()
    Chat("All points reset.")
end)

-- Points System Channel
local pointsTab = serv:Channel("Points System")

local targetPlayer
local pointsToAdd

pointsTab:Textbox("Target", "Enter player name", true, function(value)
    targetPlayer = getTargetPlayer(value)
    print("Target Player: ", targetPlayer)
end)

pointsTab:Textbox("Amount of points", "0", true, function(value)
    if value and tonumber(value) then
        pointsToAdd = value
    end
    print("Points to add: ", pointsToAdd)
end)

pointsTab:Button("Apply points", function()
    print("Apply Points Button Clicked")
    if pointsToAdd then
        if targetPlayer == "ALL" then
            for _, player in ipairs(game.Players:GetPlayers()) do
                pointManager.AddPoints(player, pointsToAdd, "Global")
            end
            Chat("➕ - "..pointsToAdd.." points have been added to everyone.")
        elseif targetPlayer then
            pointManager.AddPoints(targetPlayer, pointsToAdd, "Global")
            Chat("➕ - "..targetPlayer.DisplayName.. "'s points have been increased by ".. pointsToAdd.. ".")
        else
            Chat("❌ - Target player not found.")
        end
    end
end)

pointsTab:Button("Decrease points", function()
    print("Decrease Points Button Clicked")
    if pointsToAdd then
        if targetPlayer == "ALL" then
            for _, player in ipairs(game.Players:GetPlayers()) do
                pointManager.AddPoints(player, -pointsToAdd, "Global")
            end
            Chat("➖ - "..pointsToAdd.." points have been decreased from everyone.")
        elseif targetPlayer then
            pointManager.AddPoints(targetPlayer, -pointsToAdd, "Global")
            Chat("➖ - "..targetPlayer.DisplayName.. "'s points have been decreased by ".. pointsToAdd.. ".")
        else
            Chat("❌ - Target player not found.")
        end
    end
end)

pointsTab:Button("Reset points", function()
    print("Reset Points Button Clicked")
    if targetPlayer == "ALL" then
        for _, player in ipairs(game.Players:GetPlayers()) do
            pointManager.ClearGlobalPointsForPlayer(player)
        end
        Chat("All players' points have been reset.")
    elseif targetPlayer then
        pointManager.ClearGlobalPointsForPlayer(targetPlayer)
        Chat(targetPlayer.DisplayName.. "'s points have been reset.")
    else
        Chat("❌ - Target player not found.")
    end
end)

-- Settings Channel
local settingsTab = serv:Channel("Settings")

settingsTab:Dropdown("Mode", {"Query", "Multiple"}, function(mob)
    mode = mob:lower()
    if mob == "Query" then
        Chat("❓ - Query mode initialized.")
    elseif mob == "Multiple" then
        Chat("🅺❕ - Multiple mode initialized.")
    end
end)

settingsTab:Toggle("Autopick category", false, function(value)
    settings.autoplay = value
end)

settingsTab:Textbox("Queries cooldown", "13", true, function(value)
    if value then
        settings.questionTimeout = tonumber(value)
    end
end)

settingsTab:Textbox("Wrong answer cooldown", "3", true, function(value)
    if value then
        settings.userCooldown = tonumber(value)
    end
end)

settingsTab:Textbox("Autosend skibidi leaderboard when queries end", "3", true, function(value)
    if value then
        settings.sendLeaderBoardAfterQuestions = tonumber(value)
    end
end)

settingsTab:Toggle("Disable autosend skibidi leaderboard", false, function(value)
    settings.automaticServerQueryLeaderboard = not value
end)

settingsTab:Toggle("Disable autorepeat tagged message", false, function(value)
    if not oldChat then
        settings.repeatTagged = not value
    end
end)

if boothGame then
    settingsTab:Toggle("Disable sign status (booth game only)", false, function(value)
        settings.signStatus = not value
    end)
    settingsTab:Toggle("Don't use roman numbers for sign timer (may get tagged)", false, function(value)
        settings.romanNumbers = not value
    end)
end

-- Other Channel
local otherTab = serv:Channel("Other")

otherTab:Button("Load Infinite Yield", function()
    loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))()
end)

-- Destroy GUI Channel
local destroyTab = serv:Channel("Destroy GUI")

destroyTab:Button("Destroy GUI", function()
    DiscordLib:Destroy()
end)

-- Initialize the DiscordLib UI
win:Server("by dawid#7205")
