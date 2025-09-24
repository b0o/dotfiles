; extends
((inline) @injection.content
  (#lua-match? @injection.content "^%s*import%s")
  (#set! injection.language "tsx"))
((inline) @injection.content
  (#lua-match? @injection.content "^%s*export%s")
  (#set! injection.language "tsx"))
