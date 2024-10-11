local letters = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}
local userCooldowns = {}
local currentQuestion
local questionAnsweredBy
local quizRunning = false
local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
local blockedPlayers = {}
local whiteListedplayers = {}
local mode = "Quiz"
local answeredCorrectly = {}
local submittedAnswer = {}
local awaitingAnswer = false
local questionPoints = 1
local timeSinceLastMessage = tick()
local placeId = game.PlaceId
local replicatedStorage = game:GetService("ReplicatedStorage")
local starterGui = game:GetService("StarterGui")
local textChatService = game:GetService("TextChatService")
local quizCooldown = false
local answerOptionsSaid = 0 -- how many answer options have been said (0 = none, 1 = a, 2 = b, etc.). Prevents users from spamming letters before they even know what the corresponding answer option is
local minMessageCooldown = 2.3 -- how much you need to wait to send another message to avoid ratelimit
local whiteListEnabled = false
local ContextActionService = game:GetService("ContextActionService")

local settings = {
    questionTimeout = 10,
    userCooldown = 5,
    sendLeaderBoardAfterQuestions = 5,
    automaticLeaderboards = true,
    automaticCurrentQuizLeaderboard = true,
    automaticServerQuizLeaderboard = true,
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

local function roundNumber(num, numDecimalPlaces)
    return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end

local function notify(title: string, text: string, buttonOptions: table?)
    buttonOptions = buttonOptions or {}
    starterGui:SetCore("SendNotification", {
        Title = title,
        Text = text,
        Callback = buttonOptions.Callback,
        Button1 = buttonOptions.Button1,
        Button2 = buttonOptions.Button2
    })
end
local function EscapePattern(pattern: string) -- escapse magic characters in pattern
    local escapePattern = "[%(%)%.%%%+%-%*%?%[%]%^%$]"
    return string.gsub(pattern, escapePattern, "%%%1")
end

local antiFilteringDone: boolean
local importantMessageSent: boolean -- if a important message that needs to be resent if filtered has been sent recently
local messageBeforeFilter: string
local answeredByAltMessage: string -- alt message specially for the correct answer text
local mainQuestionSent: boolean
local messageFiltered: boolean -- set to false once main question gets asked successfully without being filtered
function SendMessageWhenReady(message: string, important: boolean?, altMessage: string?) -- sends message so roblox won't rate limit it. if message is "important", script will send it again if it gets filtered/tagged first time. Altmessage is the message to send instead of original if it gets tagged
    if not quizRunning then
        return
    end
    if not settings.repeatTagged then
        important = false
    end
    if important then
        importantMessageSent = true
        messageBeforeFilter = message
        answeredByAltMessage = altMessage
        messageFiltered = false
        antiFilteringDone = false
    end
    if tick() - timeSinceLastMessage >= minMessageCooldown then
        Chat(message)
        timeSinceLastMessage = tick()
    else
        task.wait(minMessageCooldown - (tick() - timeSinceLastMessage))
        if not quizRunning then
            return
        end
        Chat(message)
        timeSinceLastMessage = tick()
    end
    if important then
        while (not antiFilteringDone or mainQuestionSent) and quizRunning do -- yields until the anti filter functions have done their job
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

local endMessage = "Quiz ended"
if localPlayer.UserId == 2005147350 then
    endMessage = "Quiz ended"
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

function question.New(quesitonText: string, options: table, value: number)
    local newQuestion = {}
    newQuestion.mainQuestion = quesitonText
    newQuestion.answers = options
    newQuestion.rightAnswer = letters[1]
    newQuestion.rightAnswerIndex = 1
    value = value or 1
    newQuestion.value = value
    setmetatable(newQuestion, question)
    return newQuestion
end

function question:Ask()
    if not quizRunning then
        return
    end
    answerOptionsSaid = 0
    local rightAnswerBeforeShuffle = self.answers[self.rightAnswerIndex]
    self.answers = Shuffle(self.answers)
    self.rightAnswerIndex = table.find(self.answers, rightAnswerBeforeShuffle)
    self.rightAnswer = letters[self.rightAnswerIndex]
    if self.value > 1 then
        SendMessageWhenReady("⭐ | "..self.value.."x points for question")
        task.wait(2)
    end
    questionAnsweredBy = nil
    UpdateSignText(self.mainQuestion)
    currentQuestion = self
    questionPoints = self.value
    mainQuestionSent = true
    SendMessageWhenReady("🎙️ | "..self.mainQuestion, true)
    if messageFiltered then
        task.wait(3)
        Chat("➡️ | Repeated filtering detected. Skipping to the next question...")
        return false
    end
    if not quizRunning then
        return true
    end
    task.wait(CalculateReadTime(self.mainQuestion))
    for i, v in ipairs(self.answers) do
        if questionAnsweredBy or not quizRunning then
            return true
        end
        if i ~= 1 then
            task.wait(CalculateReadTime(v))
        end
        if questionAnsweredBy or not quizRunning then
            return true
        end
        SendMessageWhenReady(letters[i]..")"..v, true) -- 1 = A) 2 = B) 3 = C) etc.
        answerOptionsSaid = i
    end
end

local function SplitIntoMessages(itemTable: table, separtor: string, waitTime: number?) -- split table into multiple messages to prevent roblox cutting down the message
    local tempItemList = {}
    local messages = {}
    local currentLength = 0
    for _, item in pairs(itemTable) do
        if quizRunning then
            return
        end
        if currentLength + #item + (#separtor * #tempItemList) + 6 >= maxCharactersInMessage then -- maxCharactersInMessage characters is the limit for chat messages in Roblox. For each item, we are adding a sepatator. +6 at end for " [x/x]" at the end of message
            local conctatTable = table.concat(tempItemList, separtor)
            table.insert(messages, conctatTable)
            table.clear(tempItemList)
            table.insert(tempItemList, item)
            currentLength = #item
        else
            table.insert(tempItemList, item)
            currentLength = currentLength + #item
        end
    end
    if not quizRunning then
        table.insert(messages, table.concat(tempItemList, separtor))
    end
    for messageIndex, message in messages do
        local messageNumberString = string.format("(%d/%d)", messageIndex, #messages) -- [current message/amount of messages]
        if messageIndex == 2 or messageIndex == 3 then
            Chat("Waiting for filter...") -- hacky solution that prevents the second message getting filtered
            task.wait(6)
        end
        Chat(message.." "..messageNumberString)
        task.wait(waitTime or CalculateReadTime(message) * 0.7) -- multiplied by 0.7 because full read time is too long
        if quizRunning then
            return
        end
    end
end

local antiAfkEnabled = false
local function EnableAntiAfk() -- prevents Roblox kicking the player after 20 minutes of inactivity
    -- credit to IY for antiafk code: https://github.com/EdgeIY/infiniteyield/tree/master
    if antiAfkEnabled then
        return
    end
    local GC = getconnections or get_signal_cons
	if GC then
		for i, v in pairs(GC(localPlayer.Idled)) do
			if v["Disable"] then
				v["Disable"](v)
			elseif v["Disconnect"] then
				v["Disconnect"](v)
			end
		end
	else
		local VirtualUser = cloneref(game:GetService("VirtualUser"))
		localPlayer.Idled:Connect(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
	end
    antiAfkEnabled = true
    notify("Anti-AFK enabled successfully", "You will not get kicked for being idle")
end

--- Category OOP ---
local categoryManager = {}
local categories = {}
categories.categoryList = {}
categories.numberOfDifficulties = {}
categoryManager.__index = categoryManager

--[[Category table reference:
categories = {
    categoryList = {
        categoryName = {
            easy = {{quiz1Questions}, {quiz2Questions}},
            medium = {...},
            ...
        },
        categoryName2 = {
            easy = {{quiz1Questions}, {quiz2Questions}},
            medium = {...},
            ...
        }
    }
    numberOfDifficulties = {
        categoryName = 2
        categoryName2 = 3
        ...
    }
}
]]--

local difficultyOrder = {"", "easy", "medium", "hard"} -- the order in which difficulties should appear when sending the category list
function categoryManager.New(categoryName: string, difficulty: string?)
    difficulty = difficulty or "" -- if difficulty is not specified, use blank
    difficulty = string.lower(difficulty)
    if not categories.categoryList[categoryName] then
		categories.categoryList[categoryName] = {}
        categories.numberOfDifficulties[categoryName] = 0
	end
    if not categories.categoryList[categoryName][difficulty] then
		categories.categoryList[categoryName][difficulty] = {}
        categories.numberOfDifficulties[categoryName] += 1
        if not table.find(difficultyOrder, difficulty) then
            table.insert(difficultyOrder, difficulty)
        end
	end
    table.insert(categories.categoryList[categoryName][difficulty], {})
    local newCategory = categories.categoryList[categoryName][difficulty][#categories.categoryList[categoryName][difficulty]] -- get the new category at the end of it's difficulty table
    setmetatable(newCategory, categoryManager)
    return newCategory
end

function categoryManager:Add(quesitonText: string, options: table, value: number?, customQuestion: table?)
    self = customQuestion or self
    local newQuestion = question.New(quesitonText, options, value)
    table.insert(self, newQuestion)
end

--- Points OOP ---
local pointManager = {}
local userPoints = {}
pointManager.__index = pointManager
local UpdateUILeaderboard, ClearLeaderboardLabels -- defined later

function pointManager.NewAccount(player)
    userPoints[player.Name] = {}
    local playerPoints = userPoints[player.Name]
    playerPoints.GlobalPoints = 0
    playerPoints.CurrentQuizPoints = 0
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
        if quizRunning then
            playerAccount.CurrentQuizPoints += points
        end
    elseif playerAccount[type] then
        playerAccount[type] += points
    end
    UpdateUILeaderboard(type)
end

function pointManager.ClearQuizPointsForPlayer(player)
    local playerAccount = userPoints[player.Name]
    if not playerAccount then
        return
    end
    playerAccount.CurrentQuizPoints = 0
end

function pointManager.ClearQuizPoints()
    for _, v in pairs(userPoints) do
        v.CurrentQuizPoints = 0
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
        v.CurrentQuizPoints = 0
    end
    ClearLeaderboardLabels("CurrentQuizPoints")
    ClearLeaderboardLabels("GlobalPoints")
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
    if not currentQuestion or questionAnsweredBy or table.find(userCooldowns, player.Name) or table.find(blockedPlayers, player.Name) or table.find(submittedAnswer, player.Name) or (whiteListEnabled and not table.find(whiteListedplayers, player.Name)) then
        return
    end
    local matchAnswer
    local minLenght = 4
    if #currentQuestion.answers[currentQuestion.rightAnswerIndex] < minLenght then
        minLenght = #currentQuestion.answers[currentQuestion.rightAnswerIndex] -- if minlenght is higher the the lenght of the correct answer, decrease it
    end
    local escapedMessage = EscapePattern(messageContent)
    if #messageContent >= minLenght then
        for _, v in ipairs(currentQuestion.answers) do
        local escapedAnswer = EscapePattern(v)
            if v:upper() == messageContent then
                matchAnswer = v
                break
            elseif (string.match(v:upper(), escapedMessage) and #string.match(v:upper(), escapedMessage) >= minLenght) or string.match(messageContent, escapedAnswer:upper()) then
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
            if mode == "Quiz" then
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
        elseif mode == "Quiz" then
            if awaitingAnswer then
                requestSendMessage("❌ | "..player.DisplayName.." wrong answer. Try again in "..tostring(settings.userCooldown).." seconds")
            end
            table.insert(userCooldowns, player.Name)
            task.delay(settings.userCooldown, function()
                table.remove(userCooldowns, table.find(userCooldowns, player.Name))
            end)
        elseif mode == "Kahoot" then
            table.insert(submittedAnswer, player.Name)
        end
    end
end

local filtersInARow = 0
local function processMessage(player: Player, message: string)
    if player ~= localPlayer then
        startChatListening(message, player)
    else
        if not (importantMessageSent or mainQuestionSent) or not quizRunning or not messageBeforeFilter then
            return
        end
        message = string.gsub(message, "&amp;", "&") -- for some very strange reason, & gets picked up as &amp;? Therefore I have to replace it back. If anyone finds out why, please let me know
        if messageBeforeFilter == message or (answeredByAltMessage and string.find(message, answeredByAltMessage)) then -- if message before and after filtering are exactly the same, the message has not been filtered
            filtersInARow = 0
            messageFiltered = false
            mainQuestionSent = false
            antiFilteringDone = true
            return
        elseif math.abs(#message - #messageBeforeFilter) > 8 or not string.find(message, "#") then -- if the lenght is diffrent from messageBeforeFilter the message is unrelated. Also give some space for diffrence to account for roblox weirdness with filtered lengh being diffrent from original lenght. Also checks for # to see if at least part of the message got tagged
            return
        elseif mainQuestionSent and messageFiltered then -- if the main question got sent once and got filtered, don't try again
            mainQuestionSent = false
            antiFilteringDone = true
            return
        end
        messageFiltered = true
        filtersInARow += 1
        if filtersInARow == 1 then
            SendMessageWhenReady("🔁 | Waiting for filter to clear and resending filtered message...")
            task.wait(5) -- waiting makes the the filtering system less agressive
        elseif filtersInARow == 2 then
            SendMessageWhenReady("🔁 | Resending previous message because of chat filter...")
            task.wait(6)
        else
            SendMessageWhenReady("Attempting to get around Roblox tagging")
            task.wait(6)
            filtersInARow = 0
        end
        if not quizRunning then
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
    if not quizRunning then
        return
    end
    awaitingAnswer = true
    local timeIsOut = false
    local function Timeout()
        if not quizRunning then
            return
        end
        task.wait(settings.questionTimeout)
        UpdateSignText(targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex])
        SendMessageWhenReady("⏰ | Time is out! Correct answer was: "..targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex], true)
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

    if mode == "Quiz" then
        while questionAnsweredBy == nil and not timeIsOut and quizRunning do
            task.wait()
        end
        if timeIsOut or not quizRunning then
            return
        end
        coroutine.close(timeoutCoroutine)
        coroutine.close(signTimeCoroutine)
        pointManager.AddPoints(questionAnsweredBy, targetQuestion.value)
        task.delay(0.5, function() -- delayed to give time to the signtimecoroutine to stop chanong sign text
            UpdateSignText(targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex])
        end)
        SendMessageWhenReady("✔️ | "..questionAnsweredBy.DisplayName.." answered correctly. Answer was: "..targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex], true, "[Player name filtered] answered correctly. Answer was: "..targetQuestion.rightAnswer..")"..targetQuestion.answers[targetQuestion.rightAnswerIndex])
        questionAnsweredBy = nil
        awaitingAnswer = false
        table.clear(userCooldowns)
    else
        while not timeIsOut and quizRunning do
            task.wait(1)
            questionPoints -= questionPoints / settings.questionTimeout
        end
        task.wait(2)
        if not quizRunning then
            return
        end
        if #answeredCorrectly > 0 then
            local tempuserList = {} -- split players into multiple messages to prevent roblox cutting down the message
            local currentLength = 37
            local firstIteration = true
            for _, user in pairs(answeredCorrectly) do
                if currentLength + #user + (2 * #tempuserList) >= maxCharactersInMessage then -- maxCharactersInMessage is the limit for chat messages in Roblox. For each user, we are adding 2 more characters (, )
                    if firstIteration then
                        SendMessageWhenReady("✔️ | Players who answered correctly: "..table.concat(tempuserList, ", "))
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
                    SendMessageWhenReady("✔️ | Players who answered correctly: "..table.concat(tempuserList, ", "))
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

local countriesEasy = categoryManager.New("Guess the country", "easy")
countriesEasy:Add("What country is this? 🇹🇷", {"Turkey", "Spain", "Greece", "Cyprus"})
countriesEasy:Add("What country is this? 🇪🇸", {"Spain", "Portugal", "Greece", "Mexico"})
countriesEasy:Add("What country is this? 🇵🇱", {"Poland", "Indonesia", "Austria", "Greenland"})
countriesEasy:Add("What country is this? 🇮🇳", {"India", "Pakistan", "Sri Lanka", "Afghanistan"})
countriesEasy:Add("What country is this? 🇳🇴", {"Norway", "Sweden", "Denmark", "Iceland"}, 2)

local countriesEasy2 = categoryManager.New("Guess the country", "easy")
countriesEasy2:Add("What country is this? 🇫🇷", {"France", "England", "Netherlands", "Russia"})
countriesEasy2:Add("What country is this? 🇬🇷", {"Greece", "Serbia", "Argentina", "Spain"})
countriesEasy2:Add("What country is this? 🇦🇷", {"Argentina", "Honduras", "Estonia", "Brazil"})
countriesEasy2:Add("What country is this? 🇻🇳", {"Vietnam", "China", "Japan", "Bejing"})
countriesEasy2:Add("What country is this? 🇷🇸", {"Serbia", "Bosnia", "Croatia", "Slovakia"}, 2)

local countriesMedium = categoryManager.New("Guess the country", "medium")
countriesMedium:Add("What country is this? 🇲🇽", {"Mexico", "Netherlands", "Iran", "Spain"})
countriesMedium:Add("What country is this? 🇵🇹", {"Portugal", "Brazil", "Madrid", "Spain"})
countriesMedium:Add("What country is this? 🇲🇦", {"Morocco", "Vietnam", "China", "Israel"}, 2)
countriesMedium:Add("What country is this? 🇧🇪", {"Belgium", "Germany", "France", "Romania"})
countriesMedium:Add("What country is this? 🇮🇩", {"Indonesia", "Poland", "Peru", "Switzerland"})

local countriesHard = categoryManager.New("Guess the country", "hard")
countriesHard:Add("What country is this? 🇸🇮", {"Slovenia", "Slovakia", "Russia", "Serbia"})
countriesHard:Add("What country is this? 🇪🇷", {"Eritrea", "Ecuador", "El Salvador"})
countriesHard:Add("What country is this? 🇫🇮", {"Finland", "Sweden", "Falkland Islands"})
countriesHard:Add("What country is this? 🇿🇲", {"Zambia", "Zimbabwe", "Zaire"}, 2)
countriesHard:Add("What country is this? 🇸🇴", {"Somalia", "Solomon Islands", "Samoa"})

local science = categoryManager.New("Science")
science:Add("The standard unit of measurement used for measuring force is which of the following?", {"Newton", "Mile", "Watt", "Kilogram"})
science:Add("How long does it take the earth to do one full rotation of the sun?", {"365 days", "7 days", "30 days"})
science:Add("Oil, natural gas and coal are examples of …", {"Fossil fuels", "Renewable resources", "Biofuels", "Geothermal resources"}, 2)
science:Add("Why do our pupils constrict in bright light?", {"To let in less light", "To give our eyes more oxygen", "To change our vision to 3D"})
science:Add("What is cooling lava called?", {"Igneous rocks", "Magma", "Fossils"})

local science2 = categoryManager.New("Science")
science2:Add("What is faster, sound or light?", {"Light", "Sound", "They travel at the same speed", "They don't move"})
science2:Add("Which of these is not one of Newton's laws of motion?", {"Objects at rest stay in motion", "Force equals mass times acceleration", "Every action has an equal and opposite reaction", "An object in motion stays in motion"})
science2:Add("Who developed the theory of relativity?", {"Albert Einstein", "Isaac Newton", "Galileo"})
science2:Add("Which of these is not a state of matter?", {"Energy", "Solid", "Liquid", "Gas"})
science2:Add("What is the powerhouse of the cell?", {"Mitochondria", "Nucleus", "Cytoplasm", "Nucleic membrane"}, 2)

local history = categoryManager.New("History")
history:Add("Which of these countries did the Soviet Union NEVER invade?", {"Sweden", "Afghanistan", "Finland", "Poland"})
history:Add("What was the main cause of the French Revolution in 1789?", {"The social and economic inequality of the Third Estate", "The invasion of Napoleon Bonaparte", "The death of King Louis XVI", "The spread of the Black Death"})
history:Add("Which of these historical events happened first?", {"The American Revolution", "The French Revolution", "The Industrial Revolution", "The Russian Revolution"}, 2)
history:Add("What ancient civilization built the Machu Picchu complex?", {"Inca", "Aztec", "Maya", "Egypt"})
history:Add("In what modern-day country was Karl Marx, the communist philosopher, born?", {"Germany", "France", "Russia", "China"}, 2)

local history2 = categoryManager.New("History")
history2:Add("The disease that killed a third of Europe's population in the 14th century is known as:", {"Plague (Black Death)", "Spanish Flu", "Smallpox", "Malaria"})
history2:Add("What famous rifle is known in America as 'The Gun that Won the West?'", {"Winchester Model 1873", "Henry Repeating Rifle", "Colt Peacemake", "Remington Army Revolver"}, 2)
history2:Add("Were Italy and the United Kingdom allies or enemies during World War One?", {"Allies", "Enmies"})
history2:Add("How were Holy Roman Emperors chosen?", {"A small group of princes elected them", "They got chosen by the pope", "Democratic vote of the people"}, 2)
history2:Add("Where and when was Siddhārtha Gautama, AKA Buddha, born?", {"Approx. 500 BC, Nepal", "Approx. 1 AD, Palestine", "Approx. 900 AD, China"})

local foodAndDrink = categoryManager.New("Food and drink")
foodAndDrink:Add("Which country is the largest producer of coffee in the world?", {"Brazil", "Vietnam", "Colombia", "Ethiopia"})
foodAndDrink:Add("What is the name of the Italian dessert made from layers of sponge cake soaked in coffee and mascarpone cheese?", {"Tiramisu", "Maritozzo", "Cannoli", "Zabaglione"})
foodAndDrink:Add("What is the main ingredient of the Spanish dish, Paella?", {"Rice", "Bread", "Pasta", "Chicken"})
foodAndDrink:Add("What is the name of the fermented milk drink that is popular in Central Asia & Eastern Europe?", {"Kefir", "Karin", "Kulmel", "Yogurt"})
foodAndDrink:Add("Which country does feta cheese come from?", {"Greece", "Switzerland", "Spain", "France"}, 2)

local trivia = categoryManager.New("Trivia")
trivia:Add("Which is NOT a Nobel Prize category?", {"Mathematics", "Physics", "Literature", "Chemistry"})
trivia:Add("Which musical instrument has 47 strings and seven pedals?", {"Harp", "Piano", "Guitar", "Violin"})
trivia:Add("What is the capital city of Japan?", {"Tokyo", "Beijing", "Seoul", "Bangkok"})
trivia:Add("Which country is the only one to have a non-rectangular flag?", {"Nepal", "Switzerland", "Japan", "Qatar"})
trivia:Add("'Bokmal' and 'Nynorsk' are the two official written forms of WHICH language?", {"Norwegian", "Italian", "Danish", "Spanish"}, 2)

local trivia2 = categoryManager.New("Trivia")
trivia2:Add("Which animal is the national emblem of Australia?", {"Kangaroo", "Koala", "Emu", "Platypus"})
trivia2:Add("What does the Richter scale measure?", {"Earthquake intensity", "Wind Speed", "Temperature", "Tornado Strength"}, 2)
trivia2:Add("Which currency is used in Japan?", {"Yen", "Dollar", "Euro", "Pound"})
trivia2:Add("Which famous scientist developed the theory of relativity?", {"Albert Einstein", "Isaac Newton", "Galileo Galilei", "Charles Darwin"})
trivia2:Add("In sport, what does the term PGA refer to?", {"Professional Golfers Association", "Par Golfing Average", "Playing Golf Average", "Part-Time Golfing Amaterurs"})

local guessTheLanguage = categoryManager.New("Guess the language")
guessTheLanguage:Add("Je suis désolé", {"French", "Spanish", "Italian", "Portuguese"})
guessTheLanguage:Add("בוקר טוב", {"Hebrew", "Tamil", "Lao", "Mandarin"})
guessTheLanguage:Add("Guten Tag", {"German", "Tagalog", "Finnish", "Dutch"})
guessTheLanguage:Add("こんにちは", {"Japanese", "Chinese", "Turkish", "Arabic"}, 2)
guessTheLanguage:Add("नमस्ते", {"Hindi", "Indonesian", "Cantonese", "Nahuatl"})

local capitals = categoryManager.New("Capitals", "easy")
capitals:Add("What is the capital city of the USA?", {"Washington D.C.", "New York City", "Los Angeles", "Austin"})
capitals:Add("What is the capital city of Finland?", {"Helsinki", "Stockholm", "Dublin", "Reykjavik"}, 2)
capitals:Add("What is the capital city of Poland?", {"Warsaw", "Kiev", "Moscow", "Krakow"})
capitals:Add("What is the capital city of Germany?", {"Berlin", "Frankfurt", "Hamburg", "Dusseldorf"})
capitals:Add("What is the capital city of Canada?", {"Ottawa", "Toronto", "Vancouver", "Montreal"})

local capitalsHard = categoryManager.New("Capitals", "hard")
capitalsHard:Add("What is the capital of Belgium?", {"Brussels", "Liege", "Amsterdam"})
capitalsHard:Add("What is the capital of Somalia?", {"Mogadishu", "Garoowe", "Berbera"})
capitalsHard:Add("What is the capital city of Mongolia?", {"Ulaanbaatar", "Hanoi", "Seoul"})
capitalsHard:Add("What is the capital city of Australia?", {"Canberra", "Sydney", "Perth"})
capitalsHard:Add("What is the capital city of New Zealand?", {"Wellington", "Auckland", "Hamilton"})

local geography = categoryManager.New("Geography", "easy")
geography:Add("Which river flows through London?", {"River Thames", "River Severn", "River Trent"})
geography:Add("On which continent is the Sahara Desert located?", {"Africa", "Asia", "Europe"})
geography:Add("Which of these cities is NOT a national capital?", {"Sydney", "Oslo", "Wellington", "Bangkok"}, 2)
geography:Add("Which of these continents has the largest land area?", {"Asia", "Africa", "Europe", "South America"})
geography:Add("What is the smallest country in the world?", {"Vatican City", "Belgium", "Luxembourd"})

local geographyMedium = categoryManager.New("Geography", "medium")
geographyMedium:Add("Which island is the largest in the world?", {"Greenland", "Madagascar", "Borneo", "New Guinea"})
geographyMedium:Add("Which continent has the most countries?", {"Africa", "Europe", "Asia", "Australia"})
geographyMedium:Add("Which one of the following countries is further north?", {"Scotland", "The Netherlands", "Belgium", "Poland"})
geographyMedium:Add("What is the longest river in the world?", {"The Nile", "Amzon River", "Yangtze River", "Yellow River"})
geographyMedium:Add("Which ocean is the deepest?", {"Pacific Ocean", "Atlantic Ocean", "Indian Ocean", "Arctic Ocean"}, 2)

local geographyHard = categoryManager.New("Geography", "hard")
geographyHard:Add("Which country has the longest coastline?", {"Canada", "Chile", "Norway", "Australia"})
geographyHard:Add("Which continent is the only one without a desert?", {"Europe", "Asia", "North America", "Africa"})
geographyHard:Add("Which one of the following countries is not an enclave?", {"Italy", "Vatican City", "San Marino", "Lasotho"}, 2)
geographyHard:Add("Which is the northernmost capital city in the world?", {"Reykjavik, Iceland", "Oslo, Norway", "Helsinki, Finland", "Moscow, Russia"})
geographyHard:Add("Which city is the only one located on two continents?", {"Istanbul", "Cairo", "Moscow", "Panama City"})

local gaming = categoryManager.New("Gaming")
gaming:Add("What is the best-selling video game of all time?", {"Minecraft", "FIFA 18", "Call of Duty: Modern Warfare 3", "Tetris"})
gaming:Add("What was the first commercially successful video game?", {"Pong", "Donkey Kong Country", "Super Mario Bros", "Spacewar"})
gaming:Add("What is the name of the main character in the Legend of Zelda series?", {"Link", "Zelda", "Ganon", "Mario"})
gaming:Add("What video game did Mario, the Nintendo character, first appear in?", {"Donkey Kong", "Super Mario Bros", "Marios Cement Factory", "Mario Bros"}, 2)
gaming:Add("What is the name of the virtual reality device developed by Valve?", {"Valve Index", "Oculus Rift", "Meta Quest", "Valve VR"})

local gaming2 = categoryManager.New("Gaming")
gaming2:Add("Which company created the Mario franchise?", {"Nintendo", "Sony", "Microsoft", "Sega"})
gaming2:Add("What is the name of the game developer who created Half-Life, Portal, and Counter-Strike?", {"Valve", "Blizzard", "Bethesda", "Rockstar"})
gaming:Add("What is the name of the gaming console that was released by Nintendo in 2006 and featured motion controls?", {"Wii", "Switch", "GameCube", "DS"})
gaming2:Add("What is the name of the platform game series that features a plumber who rescues a princess from a turtle-like villain?", {"Super Mario", "Sonic the Hedgehog", "Crash Bandicoot", "Rayman"})
gaming2:Add("How many standalone Grand Theft Auto titles have been released?", {"7", "5", "8", "10"}, 2)

local movies = categoryManager.New("Movies")
movies:Add("Which actor played the role of Jack Sparrow in the 'Pirates of the Caribbean' franchise?", {"Johnny Depp", "Orlando Bloom", "Keira Knightley", "Geoffrey Rush"})
movies:Add("What was the first movie in the Marvel Cinematic Universe?", {"Iron Man", "The Avengers", "Batman", "Spider-Man"}, 2)
movies:Add("Which movie is based on the novel by J.R.R. Tolkien?", {"The Lord of the Rings", "The Chronicles of Narnia", "The Hunger Games", "The Da Vinci Code"})
movies:Add("What is the name of the protagonist in The Matrix?", {"Neo", "Morpheus", "Trinity", "Cypher"})
movies:Add("In the movie 'Frozen', who is Olaf?", {"A snowman", "A ghost", "A knight", "A reindeer"})

local roblox = categoryManager.New("Roblox")
roblox:Add("What was the original name of Roblox?", {"DynaBlocks", "SuperBlocks", "XtraBlocks"})
roblox:Add("What is the name of Roblox's other virtual currency that has been removed since 2016?", {"Tix", "Builder Coins", "Ro-Points"})
roblox:Add("What program do you use to make games on Roblox?", {"Roblox Studio", "Roblox Player", "Roblox Create", "Roblox Creator"})
roblox:Add("Roblox's private servers were previously known as which of the following?", {"VIP servers", "Personal servers", "Exclusive servers"})
roblox:Add("Who won the RB Battles season 1 championship?", {"KreekCraft", "Tofuu", "Seedeng", "BriannaPlayz"}, 2)

local roblox2 = categoryManager.New("Roblox")
roblox2:Add("What is another name for the avatar shop?", {"Catalog", "Avatar Creator", "Avatar Editor"})
roblox2:Add("What programming language do you need to use to create Roblox games?", {"Luau", "JavaScript", "Python", "PHP"}, 2)
roblox2:Add("What is the name of Roblox's annual developer conference?", {"RDC", "Robloxcon", "Robloxx", "Blockfest"})
roblox2:Add("What was the former name of Roblox premium?", {"Builders Club", "Roblox Plus", "Roblox Pro", "VIP Club"})
roblox2:Add("What was the very first Roblox game to reach 1B+ visits?", {"MeepCity", "Arsenal", "Build a Boat For Treasure", "Adopt Me"}, 2)

local english = categoryManager.New("English")
english:Add("I'm very happy _____ in India. I really miss being there.", {"to have lived", "to live", "to be living", "to be lived"})
english:Add("They didn't reach an agreement ______ their differences.", {"on account of", "with", "because", "owing"})
english:Add("I wish I _____ those words. But now it's too late.", {"had never said", "never said", "have never said", "not having said"}, 2)
english:Add("She was working on her computer with her baby next to _____.", {"her", "them", "her own", "hers"})
english:Add("_____ in trying to solve this problem. It's clearly unsolvable.", {"There's no point", "It's no point", "There isn't point", "It's no need"})

local animals = categoryManager.New("Animals")
animals:Add("What is the largest land animal?", {"Elephant", "Giraffe", "Whale", "Rhino"})
animals:Add("What is the name of a baby kangaroo?", {"Joey", "Cub", "Pup", "Kit"})
animals:Add("Capable of exceeding 186 miles per hour, what is the fastest creature in the animal kingdom?", {"Peregrine falcon", "Cheetah", "Horse", "Lion"})
animals:Add("What is the only mammal that can fly?", {"Bat", "Penguin", "Pterodactyl", "Dragon"}, 2)
animals:Add("Which of these “fish” is actually a fish?", {"Swordfish", "Starfish", "Crayfish", "Jellyfish"})

local sports = categoryManager.New("Sports")
sports:Add("What sport is played on a field with 15 players on each team?", {"Rugby", "Soccer", "Cricket", "Lacrosse"})
sports:Add("What is the name of the trophy awarded to the winner of the NBA Finals?", {"Larry O'Brien Trophy", "NBA Champion Trophy", "Stanley Cup", "World Series Trophy"}, 2)
sports:Add("Which country is famous for inventing sumo wrestling?", {"Japan", "China", "India", "Thailand"})
sports:Add("What sport involves sliding stones on a sheet of ice towards a target area?", {"Curling", "Bobsleigh", "Luge", "Ice hockey"}, 2)
sports:Add("What sport is also known as table tennis?", {"Ping pong", "Badminton", "Squash", "Tennis"})

local minecraft = categoryManager.New("Minecraft")
minecraft:Add("What is the name of the green creature that explodes?", {"Creeper", "Zombie", "Skeleton", "Slime"})
minecraft:Add("Which tool is best for digging stone and bricks?", {"Pickaxe", "Shovel", "Axe", "Drill"})
minecraft:Add("What is the name of the dimension where you fight the Ender Dragon?", {"The End", "The Nether", "The Overworld", "The Void"}, 2)
minecraft:Add("What resource do you need to trade with villagers?", {"Emerald", "Apple", "Gold", "Iron"})
minecraft:Add("What block can you use to make a portal to the Nether?", {"Obsidian", "Netherrack", "Cobblestone", "Bedrock"})

local chess = categoryManager.New("Chess")
chess:Add("What is the name of the piece that can only move diagonally?", {"Bishop", "Knight", "Queen"})
chess:Add("What is the term for a situation where a king is under attack and cannot escape?", {"Checkmate", "Stalemate", "En passant", "Castling"})
chess:Add("What is the name of the chess strategy that involves sacrificing a piece to gain an advantage?", {"Gambit", "Fork", "Pin", "Skewer"})
chess:Add("What is the name of the special move where a king and a rook swap places?", {"Castling", "Promotion", "Capture", "Fork"})
chess:Add("Which piece is involved in 'en passant'?", {"Pawn", "Queen", "Bishop", "Knight"}, 2)

local WWII = categoryManager.New("WWII")
WWII:Add("Which countries formed the Axis powers in WWII?", {"Germany, Italy and Japan", "France, Britain and Russia", "China, India and Australia", "Canada, Mexico and Brazil"})
WWII:Add("Which country was attacked by Japan in 1941, prompting its entry into WWII?", {"USA", "China", "India", "Australia"})
WWII:Add("Which two countries were the first to declare war on Germany?", {"Britain and France", "Italy and Greece", "Norway and Denmark", "Poland and Russia"})
WWII:Add("What was the name of the operation that marked the Allied invasion of Normandy in 1944?", {"Operation Overlord", "Operation Barbarossa", "Operation Torch", "Operation Garden"}, 2)
WWII:Add("What was the name of the code-breaking machine developed by the British to crack German ciphers?", {"Bombe", "Turing", "Lorenz", "Enigma"})

local WWI = categoryManager.New("WWI")
WWI:Add("Which country made the first declaration of war in WWI?", {"Austria-Hungary", "Serbia", "Russia", "Germany"})
WWI:Add("What was the name of the British passenger ship that was sunk by a German submarine in 1915?", {"Lusitania", "Titanic", "Britannia", "Olympic"})
WWI:Add("What was the nickname given to the type of warfare that involved digging trenches and fighting from them?", {"Trench warfare", "Guerrilla warfare", "Dirt warfare", "Siege warfare"})
WWI:Add("What caused Great Britain to join World War I?", {"German troops marching through Belgium", "German bombing raids on London", "German use of illegal chemicals", "Germans sinking British civilian ships"})
WWI:Add("What was the name of the alliance between Germany, Austria-Hungary and Italy?", {"Triple Alliance", "The Axis Powers", "The Triple Entente", "The League of Nations"}, 2)

local luau = categoryManager.New("Luau")
luau:Add("What is the keyword for defining a function in Luau?", {"function", "def", "local", "sub"})
luau:Add("What is the syntax for creating a comment in Luau?", {"-- comment", "// comment", "# comment", "' comment"}, 2)
luau:Add("What is the data type for storing multiple values in Luau?", {"table", "array", "list", "set"})
luau:Add("How do you declare a table in Luau?", {"local table = {}", "local table = []", "local table = table.new()", "local table = ()"})
luau:Add("What is the symbol for concatenating strings in Luau?", {"..", "+", "&", "%"}, 2)

local astronomy = categoryManager.New("Astronomy")
astronomy:Add("What is the name of the dwarf planet that was once considered a ninth planet in our solar system?", {"Pluto", "Ceres", "Eris", "Haumea"})
astronomy:Add("What is the name of the theory that describes how the universe began with a massive expansion from a single point?", {"The Big Bang theory", "The Steady State theory", "The Inflationary theory", "The String theory"})
astronomy:Add("What is the name of the largest planet in our solar system?", {"Jupiter", "Saturn", "Earth", "Neptune"})
astronomy:Add("What is the term for a group of stars that form a recognizable pattern?", {"A constellation", "A nebula", "A cluster", "A galaxy"})
astronomy:Add("What is the name of the largest moon in our solar system?", {"Ganymede", "Titan", "Io", "Europa"}, 2)

local memes = categoryManager.New("Memes")
memes:Add("Which meme features a dog sitting in a burning room?", {"This is fine", "Doge", "Grumpy Cat", "Bad Luck Brian"})
memes:Add("What is the name of the frog character that is often associated with the phrase 'feels good man'?", {"Pepe", "Kermit", "Frogger", "Freddy"}, 2)
memes:Add("What is the term for a meme that looks low-quality and pixelated?", {"Deep fried", "Dank", "Cringe", "Ironic"})
memes:Add("Which animal is associated with the 'Doge' meme?", {"Shiba Inu", "Grumpy Cat", "Keyboard Cat", "Nyan Cat"})
memes:Add("What is the name of the meme featuring a man's head sticking out of a while toilet bowl?", {"Skibidi Toilet", "TF2 Guy", "Fanum Tax", "Smurf Cat"})

local anarchy = categoryManager.New("Anarchy")
anarchy:Add("What does the word 'anarchy' mean?", {"Absence of government and absolute freedom of the individual", "A state of disorder due to absence or nonrecognition of authority", "A political ideology that advocates self-governance and voluntary associations", "A system of social organization based on mutual aid and cooperation"})
anarchy:Add("Which of these symbols is commonly associated with anarchy?", {"A circled A", "A hammer and sickle", "A peace sign", "A red star"})
anarchy:Add("Which anarchist principle asserts that individuals should be free to pursue their interests and preferences, without being constrained by any fixed or imposed roles, norms, or identities?", {"Individualism", "Egoism", "Existentialism", "Nihilism"})
anarchy:Add("Which of these contemporary movements is inspired by anarchist principles?", {"Occupy Wall Street", "Black Lives Matter", "Extinction Rebellion", "All of the above"}, 2)
anarchy:Add("Which of these genres of music is often linked to anarchy?", {"Punk rock", "Classical music", "Country music", "Blues"})

local anime = categoryManager.New("Anime")
anime:Add("What is the name of the main character in Naruto?", {"Naruto Uzumaki", "Sasuke Uchiha", "Kakashi Hatake", "Itachi Uchiha"})
anime:Add("What is the name of the pirate crew that Monkey D. Luffy leads in One Piece?", {"Straw Hat Pirates", "Blackbeard Pirates", "Red Hair Pirates", "Whitebeard Pirates"})
anime:Add("What is the name of the powerful notebook that can kill anyone whose name is written in it in it?", {"Death Note", "Kira Note", "Shinigami Note", "Life Note"})
anime:Add("What is the main character's power in 'My Hero Academia'?", {"One For All", "All For One", "Half-Cold Half-Hot", "Explosion"}, 2)
anime:Add("What is the name of the forest spirit that Satsuki and Mei befriend in My Neighbor Totoro?", {"Totoro", "Catbus", "Kodama", "Makkuro Kurosuke"})

local scienceHard = categoryManager.New("Science", "hard")
scienceHard:Add("What is the name of the largest bone in the human body?", {"Femur", "Humerus", "Tibia", "Pelvis"})
scienceHard:Add("Which of these particles is its own antiparticle?", {"Photon", "Proton", "Electron", "Neutron"})
scienceHard:Add("What is the name of the phenomenon in which light is scattered by particles in a medium that are not much larger than the wavelength of the light?", {"Rayleigh scattering", "Diffraction", "Refraction", "Dispersion"}, 2)
scienceHard:Add("What is the name of the branch of mathematics that deals with the properties and relationships of abstract entities such as numbers, symbols, sets, and functions?", {"Algebra", "Geometry", "Calculus", "Logic"})
scienceHard:Add("What is the name of the unit of electric potential difference, electric potential energy per unit charge?", {"Volt", "Ampere", "Ohm", "Watt"})

local mathCategory = categoryManager.New("Math", "easy")
mathCategory:Add("What is the value of PI (rounded to two decimal places)?", {"3.14", "3.15", "3.16", "3.17"})
mathCategory:Add("The property that states that a + b = b + a has what name?", {"Commutative property", "Associative property", "Distributive property", "Identity property"}, 2)
mathCategory:Add("What is the formula for the area of a circle?", {"pi * r^2", "2 * pi * r", "pi * d", "pi * r"})
mathCategory:Add("What is the name of the branch of mathematics that studies shapes and angles?", {"Geometry", "Algebra", "Calculus", "Arithmetic"})
mathCategory:Add("What is the value of x in the equation 2x + 5 = 13?", {"4", "3", "5", "6"})

local mathHard = categoryManager.New("Math", "hard")
mathHard:Add("What is the name of the theorem that states that a² + b² = c² for a right triangle?", {"Pythagorean theorem", "Fermat's last theorem", "Binomial theorem", "Euclid's theorem"})
mathHard:Add("What is the derivative of e^x?", {"e^x", "x*e^(x-1)", "ln(x)", "1/e^x"})
mathHard:Add("What is the name of the constant that is approximately equal to 2.71828?", {"Euler's number", "The golden ratio", "PI", "Planck's constant"})
mathHard:Add("What is the name of the sequence that starts with 1, 1, 2, 3, 5, 8, ...?", {"Fibonacci Sequence", "Arithmetic Sequence", "Geometric Sequence", "Harmonic Sequence"}, 2)
mathHard:Add("What is the name of the branch of mathematics that deals with patterns and sequences?", {"Combinatorics", "Algebra", "Calculus", "Geometry"})

local coldWar = categoryManager.New("Cold War")
coldWar:Add("In 1946 Winston Churchill popularized what term used to describe Soviet relations with Western powers?", {"Iron curtain", "Mutually assured destruction", "Quagmire", "Special relationship"})
coldWar:Add("Frequently cited as the counterpart to the CIA, what was the name of the Soviet intelligence agency?", {"KGB", "ICBM", "SALT", "DMZ"})
coldWar:Add("Devised in 1959, the DEFCON system has five stages of military readiness. Which DEFCON rating is used when a nuclear attack is imminent or already underway?", {"DEFCON 1", "DEFCON 3", "DEFCON 5"})
coldWar:Add("Although never fully leaving the organization, in 1966 what country withdrew its military from NATO and expelled NATO headquarters from its borders?", {"France", "United States", "Poland", "West Germany"})
coldWar:Add("Often seen as the Soviet version of the United States’ Vietnam quagmire, the U.S.S.R.’s 10-year-long invasion of what country began in 1979?", {"Afghanistan", "Poland", "Czechoslovakia", "Ukraine"}, 2)

local chemistry = categoryManager.New("Chemistry")
chemistry:Add("What is the chemical formula of water?", {"H2O", "CO2", "O2", "2HO"})
chemistry:Add("What is the name of the process that converts a solid into a gas without passing through a liquid state?", {"Sublimation", "Evaporation", "Condensation", "Deposition"})
chemistry:Add("What is the name of the element with the symbol K?", {"Potassium", "Calcium", "Krypton", "Kalium"})
chemistry:Add("What is the name of the process that separates a mixture of liquids based on their boiling points?", {"Distillation", "Filtration", "Crystallization", "Chromatography"})
chemistry:Add("What is the name of the organic compound that has the general formula CnH2n+2?", {"Alkane", "Alkene", "Alkyne", "Ammonia"}, 2)

local biology = categoryManager.New("Biology")
biology:Add("What is the name of the process by which plants make their own food?", {"Photosynthesis", "Respiration", "Transpiration", "Fermentation"})
biology:Add("What is the smallest unit of life?", {"Cell", "Atom", "Molecule", "Organ"})
biology:Add("What is the main function of red blood cells?", {"Oxygen transport", "Fighting infections", "Blood clotting", "Producing antibodies"})
biology:Add("What are the four types of macromolecules found in living things?", {"Carbohydrates, proteins, lipids, and nucleic acids", "Glucose, amino acids, fatty acids, and nucleotides", "Starch, enzymes, fats, and DNA", "Sugars, peptides, oils, and RNA"}, 2)
biology:Add("What is the name of the molecule that carries genetic information in most living organisms?", {"DNA", "Cell", "ATP", "ADP"})

local sayings = categoryManager.New("Sayings and Idioms")
sayings:Add("Which idiom means to reveal a secret?", {"Let the cat out of the bag", "Paint the town red", "Beat around the bush", "Bite the bullet"})
sayings:Add("What does 'a piece of cake' refer to?", {"Something very easy", "A dessert", "A difficult task", "A small portion"})
sayings:Add("Which idiom means to be in trouble?", {"In hot water", "On cloud nine", "Under the weather", "Out of the blue"})
sayings:Add("What does 'hold your horses' mean?", {"Be patient", "Ride horses", "Work hard", "Go faster"})
sayings:Add("What does 'break a leg' mean?", {"Good luck", "Actually break a leg", "Run away", "Take a break"}, 2)

local internetSlang = categoryManager.New("Internet Slang", "easy")
internetSlang:Add("What does 'LOL' stand for?", {"Laugh Out Loud", "Lots Of Love", "Living On Land", "Look Out Left"})
internetSlang:Add("What does 'FOMO' stand for?", {"Fear Of Missing Out", "Friends Of My Office", "Fond Of Moving On", "Full Of Many Options"})
internetSlang:Add("What does 'IMO' stand for?", {"In My Opinion", "Internet Mail Order", "It's Monday Obviously", "I Mean Okay"})
internetSlang:Add("What is the meaning of 'SMH'?", {"Shaking My Head", "So Much Hate", "Send More Help", "Smashing My Head"})
internetSlang:Add("What does 'IIRC' stand for?", {"If I Recall Correctly", "It Is Really Cool", "I'm Incredibly Rich, Child", "Interesting Information Requires Consideration"}, 2)

local internetSlang2 = categoryManager.New("Internet Slang", "medium")
internetSlang2:Add("What does 'FTFY' mean?", {"Fixed That For You", "For The Following Year", "Forget That, Find Yourself", "Faster Than Fifty Yaks"})
internetSlang2:Add("What is the meaning of 'AMA'?", {"Ask Me Anything", "Always Making Assumptions", "Another Missed Appointment", "Awesome Meme Alert"})
internetSlang2:Add("What does 'YOLO' stand for?", {"You Only Live Once", "Your Own Life Obligations", "Yesterday's Old Leftover Onions", "Yelling Out Loud Often"})
internetSlang2:Add("What does 'OMW' stand for?", {"On My Way", "Oh My Word", "Only Men Welcome", "Official Meme Website"})
internetSlang2:Add("What is the meaning of 'ITT'?", {"In This Thread", "I'll Tell Them", "I Think That", "I Talked To"}, 2)

local guessTheMovie = categoryManager.New("Guess the Movie")
guessTheMovie:Add("Which movie features a young wizard attending the Hogwarts School?", {"Harry Potter and the Philosopher's Stone", "The Lord of the Rings", "The Chronicles of Narnia", "The Wizard of Oz"})
guessTheMovie:Add("What movie tells the story of a clownfish searching for his son across the ocean?", {"Finding Nemo", "Shark Tale", "The Little Mermaid", "Free Billy"})
guessTheMovie:Add("Which sci-fi film features blue-skinned aliens called the Na'vi?", {"Avatar", "Star Wars", "Alien", "District 9"})
guessTheMovie:Add("In what movie does Tom Hanks play a man stranded on an island with only a volleyball for company?", {"Cast Away", "The Terminal", "Forrest Gump", "Saving Private Ryan"}, 2)
guessTheMovie:Add("What movie tells the story of a group of toys that come to life when humans aren't around?", {"Toy Story", "The Lego Movie", "Small Soldiers", "Wreck-It Ralph"})

local guessTheBook = categoryManager.New("Guess the Book")
guessTheBook:Add("In which book does a young girl named Alice fall down a rabbit hole into a fantastical world?", {"Alice's Adventures in Wonderland", "The Wonderful Wizard of Oz", "Peter Pan", "The Secret Garden"})
guessTheBook:Add("Which book tells the story of a character named Bilbo Baggins?", {"The Hobbit", "The Lord of the Rings", "The Silmarillion", "Eragon"})
guessTheBook:Add("In which dystopian novel is the phrase 'Big Brother is watching you' prominent?", {"1984", "Brave New World", "Fahrenheit 451", "The Hunger Games"})
guessTheBook:Add("Which book tells the story of a boy named Charlie who wins a golden ticket?", {"Charlie and the Chocolate Factory", "Charlie and the Giant Peach", "Wonka's Chocolate Factory", "The BFG"})
guessTheBook:Add("Which book tells the story of a boy who never grows up and lives in Neverland?", {"Peter Pan", "The Wonderful Wizard of Oz", "Alice in Wonderland", "The Chronicles of Narnia"})

local categoryTable = {}
local categoryLookupTable = {} -- categoryLookupTable is used to get the actual quiz table from formatted category name

local function UpdateCategoryTable(categoryName: string, difficulties: table)
    for difficulty, quizzes in difficulties do
        for index, quiz in quizzes do
            local listName
            if #quizzes > 1 then -- if multiple quizzes exist under the same name, add their category and index at the end to distinguish them
                listName = categoryName.."-"..difficulty..index -- ex: flags-easy1, flags-easy2
                table.insert(categoryTable, listName)
            elseif categories.numberOfDifficulties[categoryName] > 1 then -- if multiple difficulties exist but only one quiz per difficulty, only add the difficulty at the end
                listName = categoryName.."-"..difficulty -- ex: flags-hard
                table.insert(categoryTable, listName)
            else
                listName = categoryName -- ex: flags
                table.insert(categoryTable, listName)
            end
            categoryLookupTable[listName] = {quiz, difficulty}
        end
    end
end

for categoryName, difficulties in categories.categoryList do
    UpdateCategoryTable(categoryName, difficulties)
end
table.sort(categoryTable)

local function SortDifficulty(a, b)
	local aOrder = table.find(difficultyOrder, a:match("^(%a+)%d*$"))
	local bOrder = table.find(difficultyOrder, b:match("^(%a+)%d*$"))
    if not aOrder or not bOrder then
        return a < b
    elseif aOrder == bOrder then
		return a < b
	else
		return aOrder < bOrder
	end
end

local function AddToSendCategoryTable(categoryName: string, difficulties: string): string
    local formattedCategory = {}
        local iterator = 0
        for difficulty, quizzes in difficulties do
            iterator += 1
            if #quizzes > 1 then
                for index, quiz in quizzes do
                    table.insert(formattedCategory, difficulty..index) -- "easy1, easy2"
                end
            elseif categories.numberOfDifficulties[categoryName] > 1 and difficulty == "" then
                table.insert(formattedCategory, difficulty.."1") -- to make sure that categories without a difficulty also get shown
            elseif categories.numberOfDifficulties[categoryName] > 1 then
                table.insert(formattedCategory, difficulty) -- "easy"
            end
        end
        table.sort(formattedCategory, SortDifficulty) -- make sure easy always comes before medium, etc.
    if #formattedCategory > 1 then
        formattedCategory = categoryName.." ["..table.concat(formattedCategory, ", ").."]"
    else
        formattedCategory = categoryName
    end
    return formattedCategory
end

local categoriesToSend = {} -- format should be: food and drink, flags [easy, easy2, medium, hard], science [easy, hard]
for categoryName, difficulties in categories.categoryList do -- indexing categories for sending with sendCategories() function
    table.insert(categoriesToSend, AddToSendCategoryTable(categoryName, difficulties))
end
table.sort(categoriesToSend)
local function sendCategories()
    if not quizRunning then
        Chat("❓ | Quiz topics:")
        task.wait(3)
        SplitIntoMessages(categoriesToSend, ", ", 5)
    end
end

local  function IsCategoryEqual(categoryName: string, matchCategory: string, suffix: string): boolean -- true if the categories are the same with the modifies. (WWII-1, WWI) -> false (WWII-1, WWII) -> true
    if categoryName == matchCategory then
        return true
    end
    suffix = EscapePattern(suffix)
    local pattern = "^"..categoryName..suffix
    return string.match(matchCategory, pattern) ~= nil
end

local function RemoveDuplicateCategories(targetTable: table, categoryName: string, suffix: string)
    local tempTable = table.clone(targetTable) -- to prevent weird stuff from happening when the loop removes items from the table while it is actively running
    for i=1, #targetTable do
        if IsCategoryEqual(categoryName, targetTable[i], suffix) then -- remove all of the category's quizzes to prevent duplicates
            table.remove(tempTable, table.find(tempTable, targetTable[i]))
        end
    end
    return tempTable
end

local categoryDropdown
local function UpdateCategory(categoryName: string) -- reindexes the specified category
    categoriesToSend = RemoveDuplicateCategories(categoriesToSend, categoryName, " [")
    local difficulties = categories.categoryList[categoryName]
    table.insert(categoriesToSend, AddToSendCategoryTable(categoryName, difficulties))
    table.sort(categoriesToSend)
    categoryTable = RemoveDuplicateCategories(categoryTable, categoryName, "-")
    UpdateCategoryTable(categoryName, difficulties)
    table.sort(categoryTable)
    categoryDropdown:Refresh(categoryTable)
end

------------- Custom question OOP -------------
local CustomCategoryManager = {}
CustomCategoryManager.__index = CustomCategoryManager
local categoryNames = {}

function CustomCategoryManager.New(categoryName: string, difficulty: string?)
    if type(categoryName) == "string" then
        if not type(difficulty) == "string" then
            difficulty = "" -- if difficulty is not a string, use default (blank)
        end
        local newCategory = setmetatable(categoryManager.New(categoryName, difficulty), CustomCategoryManager)
        categoryNames[newCategory] = categoryName
        return newCategory
    else
        print("Custom quiz error | CategoryName is not a string")
    end
    notify("Can't add custom quiz", "See the output for more information")
end

function CustomCategoryManager:Add(quesitonText: string, options: table, value: number?)
    if type(quesitonText) == "string" then
        if type(options) == "table" then
            if #options > 1 then
                if type(value) == "nil" or type(value) == "number" then
                    categoryManager:Add(quesitonText, options, value, self)
                    UpdateCategory(categoryNames[self])
                    return
                else
                    print("Custom quiz error | question value needs to be a number or nil")
                end
            else
                print("Custom quiz error | options table need to have more than one option")
            end
        else
            print("Custom quiz error | options is not a table")
        end
    else
        print("Custom quiz error | quesitonText is not a string")
    end
    notify("Can't add custom question", "See the output for more information")
end

local function getDisplayNameByUsername(username)
    local displayName = players:FindFirstChild(username) and players:FindFirstChild(username).DisplayName
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

local medalEmojis = {"🥇 ", "🥈 ", "🥉 "}
local function sendLeaderboard(type, message)
    local pointsArray
    message = message or ""
    if type == "Current quiz" then
        pointsArray = sortUserPoints("CurrentQuizPoints")
    else
        pointsArray = sortUserPoints("GlobalPoints")
    end
    task.wait(1.5)
    for i = 1, 3 do
        if pointsArray[i] and pointsArray[i][2] > 0 then
            if i == 1 then
                Chat(message..type.." leaderboard:")
            end
            local username = pointsArray[i][1]
            local displayName = getDisplayNameByUsername(username) or "" -- set to empty string in case user left during quiz
            local points = roundNumber(pointsArray[i][2], 1)
            local pointWord
            if points > 1 then
                pointWord = "points"
            else
                pointWord = "point"
            end
            task.wait(2.5)
            Chat(medalEmojis[i]..displayName.." (@"..username..") - "..points.." "..pointWord)
            UpdateSignText(medalEmojis[i]..displayName)
        end
    end
    task.wait(2.5)
end
local leaderboardLabels = {
    CurrentQuizPoints = {},
    GlobalPoints = {}
}
local function GetPointsAndUpdateLabels(type: string)
    local pointsArray = sortUserPoints(type)
    for index, label in leaderboardLabels[type] do
        if pointsArray[index] and pointsArray[index][2] > 0 then
            local username = pointsArray[index][1]
            local displayName = getDisplayNameByUsername(username)
            local points = roundNumber(pointsArray[index][2], 1)
            local pointWord
            if points > 1 then
                pointWord = "points"
            else
                pointWord = "point"
            end
            label:Set(medalEmojis[index]..displayName.." (@"..username..") - "..points.." "..pointWord)
        end
    end
end
ClearLeaderboardLabels = function(type: string) -- clears current quiz points in the UI leaderboard at the beginning of each quiz
    for index, label in leaderboardLabels[type] do
        label:Set(medalEmojis[index].." [Empty] - 0")
    end
end
UpdateUILeaderboard = function(type: string) -- updates the labels for the leaderboard in the UI
    if type ~= "All" and not leaderboardLabels[type] then
        return
    end
    if type == "All" then
        GetPointsAndUpdateLabels("GlobalPoints")
        GetPointsAndUpdateLabels("CurrentQuizPoints")
    else
        GetPointsAndUpdateLabels(type)
    end
end

local autoplayChosenCategories = {} -- categories previously chosen by autoplay
local numberOfCategoriesPerDifficulty = {}
local autoPlayDifficulties = difficultyOrder -- allowed difficulties by autoplay. Default is all difficulties
for categoryName, category in categoryLookupTable do -- find how many categories are in each difficulty group. Needed so autoplay knows when it's out of categories
    if not numberOfCategoriesPerDifficulty[category[2]] then
        numberOfCategoriesPerDifficulty[category[2]] = 1
    else
        numberOfCategoriesPerDifficulty[category[2]] += 1
    end
end
local function choseAutoplayCategory()
    local chosenCategory = categoryTable[math.random(#categoryTable)]
    local chosenCategoryDifficulty = categoryLookupTable[chosenCategory][2]
    if (autoplayChosenCategories[chosenCategoryDifficulty] and table.find(autoplayChosenCategories[chosenCategoryDifficulty], chosenCategory)) or not table.find(autoPlayDifficulties, categoryLookupTable[chosenCategory][2]) then -- if category has been previously chosen, chose another category
        return choseAutoplayCategory()
    else
        return chosenCategory
    end
end

local function startQuiz(category: string)
    if quizRunning then
        notify("A quiz is currently running", "Stop the current quiz or wait for it to end")
        return
    elseif quizCooldown then
        notify("Cooldown active", "Try again in a few seconds")
        return
    end
    quizRunning = true
    pointManager.ClearQuizPoints()
    ClearLeaderboardLabels("CurrentQuizPoints")
    Chat('🚀 | Initiating "'..category..'" quiz...')
    UpdateSignText(category)
    task.wait(3)
    local loopIterations = 0
    for _, v in pairs(categoryLookupTable[category][1]) do
        if not quizRunning then
            return
        end
        local questionAsked = v:Ask()
        if questionAsked == false then -- if question didn't get asked because of the filter, skip to next
            currentQuestion = nil
            questionAnsweredBy = nil
            task.wait(5)
            continue
        end
        awaitAnswer(v)
        if not quizRunning then
            return
        end
        task.wait(6)
        loopIterations += 1
        if not quizRunning then
            return
        end
        if loopIterations == settings.sendLeaderBoardAfterQuestions and settings.automaticLeaderboards and settings.automaticCurrentQuizLeaderboard then
            sendLeaderboard("Current quiz", "📜 | ")
            loopIterations = 0
        end
    end
    task.wait(3)
    if loopIterations ~= 0 and settings.automaticLeaderboards and settings.automaticCurrentQuizLeaderboard then
        sendLeaderboard("Current quiz", "📜 | ")
    end
    UpdateSignText(endMessage)
    task.delay(15, function()
       UpdateSignText("")
    end)
    if settings.automaticLeaderboards and settings.automaticServerQuizLeaderboard then
        sendLeaderboard("Server", "🏆 | Quiz ended. ")
        task.wait(2)
    else
        SendMessageWhenReady("🏁 | Quiz ended")
        task.wait(3)
    end
    UpdateSignText(endMessage)
    quizRunning = false
    if settings.autoplay then
        if not autoplayChosenCategories[categoryLookupTable[category][2]] then -- insert the category into autoplayChosenCategories[difficulty]
            autoplayChosenCategories[categoryLookupTable[category][2]] = {category}
        else
            table.insert(autoplayChosenCategories[categoryLookupTable[category][2]], category)
        end
        Chat("🎲 | Picking next category...")
        local autoPlayComplete = true -- true if every category has been played
        for _, difficulty in autoPlayDifficulties do -- do this each time in case the user changes the autoplay filter
            if autoplayChosenCategories[difficulty] and not #autoplayChosenCategories[difficulty] == numberOfCategoriesPerDifficulty[difficulty] then
                autoPlayComplete = false
                break
            elseif not autoplayChosenCategories[difficulty] then -- if the category has not been chosen yet at all
                autoPlayComplete = false
                break
            end
        end
        if autoPlayComplete then -- if every category has been chosen, clear the chosencategories table
            table.clear(autoplayChosenCategories)
        end
        local chosenCategory = choseAutoplayCategory()
        task.wait(6)
        startQuiz(chosenCategory)
    end
end

local quizModeRules = {"Each question has one right answer and one to three wrong answers.", "If you answer correctly, you will earn one point (or two points if the question is a double point question).", "If you answer incorrectly, you will have to wait "..tostring(settings.userCooldown).." seconds before you can submit another answer."}
local kahootModeRules = {"Each question has one right answer and one to three wrong answers.", "You can only submit ONE answer per round.", "The first answer you submit is your final answer, and it can not be changed.", "You have "..tostring(settings.questionTimeout).." seconds to answer the question after all the options have been said.", "Every second after all the options have been said, the points you will gain for answering correctly decrease.", "In other words, the quicker you answer, the more points you will gain.", "Additionally, the first person who submits a correct answer gets 1.5x points."}
local function sendRules()
    if mode == "Quiz" then
        Chat("📜 | Quiz mode rules:")
        task.wait(2)
        SplitIntoMessages(quizModeRules, " ")
    elseif mode == "Kahoot" then
        Chat("📜 | Kahoot mode rules:")
        task.wait(2)
        SplitIntoMessages(kahootModeRules, " ")
    end
end

game:GetService("Players").PlayerRemoving:Connect(function(player) -- remove player's userpoint account on leave
    pointManager.RemoveAccount(player)
end)

local function getPlayerByPlayerName(name)
    if name then
        name = string.lower(name)
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
    local matchingPlayer = getPlayerByPlayerName(name)
    if name:lower() == "me" then
        target = localPlayer
        return target
    elseif matchingPlayer then
        target = matchingPlayer
        return target
    end
    target = nil
    return target
end

local function getCategoryName(name: string) -- detects category from begging of string, for example: "gene" will return "general" category
    if #name < 2 then
        return
    end
    name = name:lower()
    for _, category in categoryTable do
        if string.lower(string.sub(category, 1, #name)) == name then
            return category
        end
    end
end
---------- UI ----------
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local success = pcall(function()
    -- You can add any additional setup if needed, 
    -- but Fluent is loaded directly above.
end)

if not success then
    notify("Quizbot error", "Failed to load UI library. Please report this bug in the Discord server:", {
        Callback = setclipboard("https://discord.gg/wm384KFFMC"),
        Button1 = "Copy invite link"
    })
end

local uiVisible = true
local function toggleUI(actionName, inputState, inputObject)
    if inputState == Enum.UserInputState.Begin then
        -- Assuming Fluent has a function to set visibility similar to Rayfield
        -- You may need to adjust this part based on Fluent's API
        uiVisible = not uiVisible
        Fluent:SetVisibility(uiVisible) -- Update this line based on Fluent's API
    end
end

ContextActionService:BindAction("ToggleUI", toggleUI, true)
ContextActionService:SetImage("ToggleUI", "rbxassetid://100698995249426")

local window = Fluent:CreateWindow({
    Title = "Quizbot | Made by Damian11",
    SubTitle = "Loading quizbot...",
    Theme = "Dark", -- Add this if you want to specify a theme
    Size = UDim2.fromOffset(580, 460), -- Set the size as needed
    Acrylic = true, -- Optional, if you want a blur effect
})

-- Add additional UI components as needed using Fluent's API

local mainTab = window:AddTab({ Title = "Main", Icon = "" }) -- Create a new tab

mainTab:AddParagraph({
    Title = "Category selection",
    Content = ""
})

local categoryLabel
local selectedCategory

mainTab:AddInput({
    Title = "Category",
    Placeholder = "Enter a category name",
    Finished = false, -- Only calls callback when you press enter
    Callback = function(value)
        selectedCategory = getCategoryName(value)
        if selectedCategory then
            Fluent:Notify({
                Title = "Selected category",
                Content = "The current category is " .. selectedCategory,
                Duration = 5
            })
            categoryLabel:Set("Selected category: " .. selectedCategory)
        end
    end
})

local categoryDropdown = mainTab:AddDropdown("Category", {
    Title = "Category",
    Values = categoryTable,
    Multi = false,
    Default = "Select a category",
    Callback = function(option)
        selectedCategory = option[1]
        categoryLabel:Set("Selected category: " .. selectedCategory)
    end
})

mainTab:AddButton({
    Title = "Send category list in chat",
    Callback = sendCategories
})

mainTab:AddParagraph({
    Title = "Quiz controls",
    Content = ""
})

categoryLabel = mainTab:AddLabel("Selected category: None")

mainTab:AddButton({
    Title = "Start quiz",
    Callback = function()
        if categoryLookupTable[selectedCategory] then
            startQuiz(selectedCategory)
        else
            Fluent:Notify({
                Title = "Invalid category",
                Content = "Select a valid category to start the quiz",
                Duration = 5
            })
        end
    end
})

mainTab:AddButton({
    Title = "Stop quiz",
    Callback = function()
        quizCooldown = true
        quizRunning = false
        currentQuestion = nil
        questionAnsweredBy = nil
        awaitingAnswer = false
        task.delay(5, function()
            quizCooldown = false
        end)
    end
})

local leaderboardTab = window:AddTab({ Title = "Leaderboard", Icon = "" })

leaderboardTab:AddParagraph({
    Title = "Server leaderboard (doesn't reset)",
    Content = ""
})

table.insert(leaderboardLabels.GlobalPoints, leaderboardTab:AddLabel("🥇 [Empty] - 0"))
table.insert(leaderboardLabels.GlobalPoints, leaderboardTab:AddLabel("🥈 [Empty] - 0"))
table.insert(leaderboardLabels.GlobalPoints, leaderboardTab:AddLabel("🥉 [Empty] - 0"))

leaderboardTab:AddButton({
    Title = "Send server leaderboard in chat",
    Callback = function()
        sendLeaderboard("Server", "🏆 | ", quizRunning)
    end
})

leaderboardTab:AddParagraph({
    Title = "Current quiz leaderboard (resets every quiz)",
    Content = ""
})

table.insert(leaderboardLabels.CurrentQuizPoints, leaderboardTab:AddLabel("🥇 [Empty] - 0"))
table.insert(leaderboardLabels.CurrentQuizPoints, leaderboardTab:AddLabel("🥈 [Empty] - 0"))
table.insert(leaderboardLabels.CurrentQuizPoints, leaderboardTab:AddLabel("🥉 [Empty] - 0"))

leaderboardTab:AddButton({
    Title = "Send current quiz leaderboard in chat",
    Callback = function()
        sendLeaderboard("Current quiz", "📜 | ", quizRunning)
    end
})

leaderboardTab:AddParagraph({
    Title = "Reset points",
    Content = ""
})

leaderboardTab:AddButton({
    Title = "Reset all points",
    Callback = pointManager.ResetAllPoints
})

local playerControlTab = window:AddTab({ Title = "Player controls", Icon = "" })
local targetPlayer
local targetPlayerLabel

playerControlTab:AddParagraph({
    Title = "Select target",
    Content = ""
})

playerControlTab:AddInput({
    Title = "Target",
    Placeholder = "Enter target name",
    OnSubmit = function(value)
        if #value < 1 then return end
        targetPlayer = getTargetPlayer(value)
        if targetPlayer then
            targetPlayerLabel:SetText("Target: " .. targetPlayer.Name)
        end
    end
})

local function TargetExists(target)
    if not target then
        notify("Invalid target", "Specify a target player")
        return false
    else
        return true
    end
end

targetPlayerLabel = playerControlTab:AddLabel("Target: None")

playerControlTab:AddParagraph({
    Title = "Modify points",
    Content = ""
})

local pointsToAdd
playerControlTab:AddInput({
    Title = "Amount of points",
    Placeholder = "Enter points amount",
    OnSubmit = function(value)
        if value and tonumber(value) then
            pointsToAdd = value
        end
    end
})

local pointsType
playerControlTab:AddDropdown({
    Title = "Apply as",
    Items = {"Server points", "Current quiz points"},
    OnSelection = function(option)
        pointsType = option
    end
})

playerControlTab:AddButton({
    Title = "Apply points",
    OnClick = function()
        if not TargetExists(targetPlayer) then return end
        if pointsToAdd then
            if pointsType == "Server points" then
                pointManager.AddPoints(targetPlayer, pointsToAdd, "GlobalPoints")
                notify("Points added", pointsToAdd .. " server points have been added to " .. targetPlayer.Name)
            elseif pointsType == "Current quiz points" then
                pointManager.AddPoints(targetPlayer, pointsToAdd, "CurrentQuizPoints")
                notify("Points added", pointsToAdd .. " current quiz points have been added to " .. targetPlayer.Name)
            else
                notify("No point type selected", "Select either server points or current quiz points to add")
            end
        else
            notify("Enter a point amount", "Enter an amount of points to add")
        end
    end
})

playerControlTab:AddButton({
    Title = "Reset global & quiz points",
    OnClick = function()
        if not TargetExists(targetPlayer) then return end
        pointManager.RemoveAccount(targetPlayer)
        notify("Points reset", "Successfully removed all points for " .. targetPlayer.Name)
    end
})

playerControlTab:AddParagraph({
    Title = "Access control",
    Content = ""
})

playerControlTab:AddButton({
    Title = "Block from participating",
    OnClick = function()
        if not TargetExists(targetPlayer) then return end
        if not table.find(blockedPlayers, targetPlayer.Name) then
            table.insert(blockedPlayers, targetPlayer.Name)
            notify("Player blocked", targetPlayer.Name .. " has been blocked from participating")
        else
            notify("Can't block player", targetPlayer.Name .. " is already blocked from participating")
        end
    end
})

playerControlTab:AddButton({
    Title = "Unblock from participating",
    OnClick = function()
        if not TargetExists(targetPlayer) then return end
        if table.find(blockedPlayers, targetPlayer.Name) then
            table.remove(blockedPlayers, table.find(blockedPlayers, targetPlayer.Name))
            notify("Player unblocked", targetPlayer.Name .. " is no longer blocked from participating")
        else
            notify("Can't unblock player", targetPlayer.Name .. " is not blocked from participating")
        end
    end
})

playerControlTab:AddButton({
    Title = "Unblock all",
    OnClick = function()
        notify("Unblocked everyone", #blockedPlayers .. " players have been unblocked")
        table.clear(blockedPlayers)
    end
})

playerControlTab:AddParagraph({
    Title = "Whitelist and blacklist",
    Content = ""
})

playerControlTab:AddToggle({
    Title = "Enable whitelist",
    State = whiteListEnabled,
    OnChange = function(value)
        whiteListEnabled = value
    end
})

playerControlTab:AddButton({
    Title = "Whitelist",
    OnClick = function()
        if not TargetExists(targetPlayer) then return end
        if not table.find(whiteListedplayers, targetPlayer.Name) then
            table.insert(whiteListedplayers, targetPlayer.Name)
            if whiteListEnabled then
                notify("Player whitelisted", targetPlayer.Name .. " has been whitelisted. The whitelist is currently enabled")
            else
                notify("Player whitelisted", targetPlayer.Name .. " has been whitelisted, but the whitelist is currently disabled")
            end
        else
            notify("Can't whitelist player", targetPlayer.Name .. " is already on the whitelist")
        end
    end
})

playerControlTab:AddButton({
    Title = "Unwhitelist",
    OnClick = function()
        if not TargetExists(targetPlayer) then return end
        if table.find(whiteListedplayers, targetPlayer.Name) then
            table.remove(whiteListedplayers, table.find(whiteListedplayers, targetPlayer.Name))
            notify("Player removed", targetPlayer.Name .. " is no longer on the whitelist")
        else
            notify("Can't remove player", targetPlayer.Name .. " is not on the whitelist")
        end
    end
})

playerControlTab:AddButton({
    Title = "Clear whitelist",
    OnClick = function()
        notify("Whitelist has been cleared", #whiteListedplayers .. " players have been removed from the whitelist")
        table.clear(whiteListedplayers)
    end
})

local settingsTab = window:CreateTab("Settings", 124411316797456)

settingsTab:CreateSection("Discord server")
settingsTab:CreateLabel("Join our Discord server for support: discord.gg/wm384KFFMC")

settingsTab:CreateButton({
    Name = "Click this button to copy the invite link",
    Callback = function()
        setclipboard("https://discord.gg/wm384KFFMC")
        notify("Successfully copied invite", "The invite link has been copied to your clipboard")
    end
})

settingsTab:CreateSection("Select mode")
settingsTab:CreateDropdown({
    Name = "Mode",
    Options = {"Quiz", "Kahoot"},
    CurrentOption = mode,
    Callback = function(option)
        mode = option[1]
        if mode == "Quiz" then
            Chat("❓ | Quiz mode enabled")
        elseif mode == "Kahoot" then
            Chat("✉️ | Kahoot mode enabled")
        end
    end
})

settingsTab:CreateButton({
    Name = "Send rules in chat",
    Callback = sendRules
})

settingsTab:CreateSection("Autoplay")
settingsTab:CreateToggle({
    Name = "Autoplay quizzes automatically",
    CurrentValue = settings.autoplay,
    Callback = function(value)
        settings.autoplay = value
        EnableAntiAfk()
    end
})

local dropdownAutoplayFilter = table.clone(difficultyOrder)
dropdownAutoplayFilter[1] = "Missing difficulty"
settingsTab:CreateDropdown({
    Name = "Autoplay filter (unselect all to disable filter)",
    Options = dropdownAutoplayFilter,
    MultipleOptions = true,
    Callback = function(options)
        local filteredTable = table.clone(options)
        if #options == 0 then
            filteredTable = difficultyOrder
        elseif table.find(filteredTable, "Missing difficulty") then
            filteredTable[table.find(filteredTable, "Missing difficulty")] = ""
        end
        autoPlayDifficulties = filteredTable
    end
})

settingsTab:CreateSection("Time settings")
settingsTab:CreateInput({
    Name = "Question timeout",
    PlaceholderText = tostring(settings.questionTimeout),
    Callback = function(value)
        if value and tonumber(value) then
            settings.questionTimeout = tonumber(value)
        end
    end
})

settingsTab:CreateInput({
    Name = "User cooldown on wrong answer",
    PlaceholderText = tostring(settings.userCooldown),
    Callback = function(value)
        if value and tonumber(value) then
            settings.userCooldown = tonumber(value)
        end
    end
})

settingsTab:CreateSection("Leaderboard settings")
settingsTab:CreateInput({
    Name = "Send current quiz LB after # of questions",
    PlaceholderText = tostring(settings.sendLeaderBoardAfterQuestions),
    Callback = function(value)
        if value and tonumber(value) then
            settings.sendLeaderBoardAfterQuestions = tonumber(value)
            if not settings.automaticCurrentQuizLeaderboard then
                notify("Current quiz LB is disabled", "This setting doesn't take effect while the automatic sending of the current quiz LB is disabled")
            end
        end
    end
})

settingsTab:CreateToggle({
    Name = "Disable automatic sending of both leaderboards",
    CurrentValue = not settings.automaticLeaderboards,
    Callback = function(value)
        settings.automaticLeaderboards = not value
    end
})

settingsTab:CreateToggle({
    Name = "Disable automatic sending of current quiz LB",
    CurrentValue = not settings.automaticCurrentQuizLeaderboard,
    Callback = function(value)
        settings.automaticCurrentQuizLeaderboard = not value
    end
})

settingsTab:CreateToggle({
    Name = "Disable automatic sending of server LB",
    CurrentValue = not settings.automaticServerQuizLeaderboard,
    Callback = function(value)
        settings.automaticServerQuizLeaderboard = not value
    end
})

settingsTab:CreateSection("Miscellaneous settings")
settingsTab:CreateToggle({
    Name = "Do not repeat tagged messages",
    CurrentValue = not settings.repeatTagged,
    Callback = function(value)
        if not oldChat then
            settings.repeatTagged = not value
        else
            notify("Can't repeat tagged", "This game uses an unsupported chat system")
        end
    end
})

if boothGame then
    settingsTab:CreateToggle({
        Name = "Disable sign status (booth game only)",
        CurrentValue = not settings.signStatus,
        Callback = function(value)
            settings.signStatus = not value
        end
    })

    settingsTab:CreateToggle({
        Name = "Don't use roman numbers for sign timer (may get tagged)",
        CurrentValue = not settings.romanNumbers,
        Callback = function(value)
            settings.romanNumbers = not value
        end
    })
end

settingsTab:CreateSection("Disable script")
settingsTab:CreateButton({
    Name = "Destroy UI and disable script",
    Callback = function()
        if oldChat then
            for _, connection in playerChatConnections do
                joinConnection:Disconnect()
                connection:Disconnect()
            end
        else
            chatConnection:Disconnect()
        end
        quizCooldown = true
        quizRunning = false
        currentQuestion = nil
        questionAnsweredBy = nil
        awaitingAnswer = false
        ContextActionService:UnbindAction("ToggleUI")
        library:Destroy()
    end
})

return CustomCategoryManager
