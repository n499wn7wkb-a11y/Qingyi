on run argv
 set helper to load script POSIX file (item 1 of argv)
 set inputHTML to "<div style=\"font-size: 20px\">A &amp; B</div><span style=\"FONT-SIZE:12.5px\">中文</span>"
 set actual to helper's prepareExistingHTML(inputHTML)
 if actual is not "<div style=\"font-size: 30px\">A &amp; B</div><span style=\"FONT-SIZE:18.75px\">中文</span>" then error "字号或正文未正确保留：" & actual
 set unchanged to "<div>没有字号的中文 &amp; English</div>"
 if helper's prepareExistingHTML(unchanged) is not unchanged then error "无字号正文被改变"
 return "PASS: HTML字号修复、多处替换、中文和正文保留、无字号内容"
end run
