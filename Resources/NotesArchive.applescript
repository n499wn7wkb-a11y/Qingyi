use framework "Foundation"
use scripting additions

on prepareExistingHTML(htmlText)
 set sourceText to current application's NSString's stringWithString:htmlText
 set mutableText to current application's NSMutableString's stringWithString:htmlText
 set regex to current application's NSRegularExpression's regularExpressionWithPattern:"(?i)(font-size\\s*:\\s*)([0-9]+(?:\\.[0-9]+)?)(px)" options:0 |error|:(missing value)
 set matches to regex's matchesInString:sourceText options:0 range:{0, sourceText's |length|()}
 repeat with i from (matches's |count|() as integer) to 1 by -1
  set aMatch to matches's objectAtIndex:(i - 1)
  set numberRange to aMatch's rangeAtIndex:2
  set oldSize to (sourceText's substringWithRange:numberRange)'s doubleValue()
  set newSize to (current application's NSNumber's numberWithDouble:(oldSize * 1.5))'s stringValue()
  mutableText's replaceCharactersInRange:numberRange withString:newSize
 end repeat
 return mutableText as text
end prepareExistingHTML

on collectFolders(theFolders, prefix)
 set resultLines to ""
 tell application "Notes"
  repeat with aFolder in theFolders
   set folderName to name of aFolder
   set folderID to id of aFolder
   set folderPath to prefix & " › " & folderName
   set resultLines to resultLines & folderID & tab & folderPath & linefeed
   set childFolders to folders of aFolder
   if (count of childFolders) > 0 then set resultLines to resultLines & my collectFolders(childFolders, folderPath)
  end repeat
 end tell
 return resultLines
end collectFolders
on run argv
 set actionName to item 1 of argv
 tell application "Notes"
  if actionName is "folders" then
   set resultLines to ""
   repeat with anAccount in accounts
    set resultLines to resultLines & my collectFolders(folders of anAccount, name of anAccount)
   end repeat
   return resultLines
  else if actionName is "read" then
   try
    set destination to folder id (item 3 of argv)
    set checkedFolderID to id of destination
   on error errorMessage number errorNumber
    if errorNumber is -1728 then error "存档文件夹不存在。" number 8102
    error errorMessage number errorNumber
   end try
   set matchingNotes to every note of destination whose id is (item 2 of argv)
   if (count of matchingNotes) is 0 then error "存档笔记不存在。" number 8101
   set targetNote to item 1 of matchingNotes
   if (count of attachments of targetNote) > 0 then error "存档笔记包含附件，无法自动追加。" number 8002
   return id of targetNote & linefeed & body of targetNote
  else if actionName is "append" then
   set folderID to item 2 of argv
   set noteID to item 3 of argv
   set titleHTML to item 4 of argv
   set entryHTML to item 5 of argv
   set duplicateEntry to (item 6 of argv is "duplicate")
   try
    set destination to folder id folderID
    set checkedFolderID to id of destination
   on error errorMessage number errorNumber
    if errorNumber is -1728 then error "存档文件夹不存在。" number 8102
    error errorMessage number errorNumber
   end try
   set targetNote to missing value
   if noteID is not "" then
    try
     set targetNote to note id noteID of destination
     set checkedNoteID to id of targetNote
    on error errorMessage number errorNumber
     if errorNumber is not -1728 then error errorMessage number errorNumber
     set targetNote to missing value
    end try
   end if
   if targetNote is missing value then
    set targetNote to make new note at destination with properties {body:"<html><head><style>body {font-size:20px} h1 {font-size:36px}</style></head><body>" & titleHTML & entryHTML & "</body></html>"}
   else
    if (count of attachments of targetNote) > 0 then error "存档笔记包含附件，无法自动追加。" number 8002
    if duplicateEntry then return "duplicate" & linefeed & id of targetNote & linefeed & body of targetNote
    set currentBody to body of targetNote
    set formattedBody to my prepareExistingHTML(currentBody)
    if body of targetNote is not currentBody then error "存档笔记已被修改，为避免覆盖，无法追加。" number 8003
    set body of targetNote to "<html><head><style>body {font-size:20px} h1 {font-size:36px}</style></head><body>" & formattedBody & "<div><br></div>" & entryHTML & "</body></html>"
   end if
   return "saved" & linefeed & id of targetNote & linefeed & body of targetNote
  else if actionName is "save" then
   set folderID to item 2 of argv
   set noteID to item 3 of argv
   set titleHTML to item 4 of argv
   set entryHTML to item 5 of argv
   set expectedBody to item 6 of argv
   set formattedBody to item 7 of argv
   set destination to folder id folderID
   if noteID is "" then
    set targetNote to make new note at destination with properties {body:"<html><head><style>body {font-size:20px} h1 {font-size:36px}</style></head><body>" & titleHTML & entryHTML & "</body></html>"}
   else
    set targetNote to first note of destination whose id is noteID
    if (count of attachments of targetNote) > 0 then error "存档笔记包含附件，为保护内容，无法自动追加。" number 8002
    set currentBody to body of targetNote
    if currentBody is not expectedBody then error "存档笔记已在备忘录中修改，请先处理后再存档，避免覆盖修改。" number 8003
    set body of targetNote to "<html><head><style>body {font-size:20px} h1 {font-size:36px}</style></head><body>" & formattedBody & "<div><br></div>" & entryHTML & "</body></html>"
   end if
   return id of targetNote & linefeed & body of targetNote
  end if
 end tell
 error "未知操作"
end run
