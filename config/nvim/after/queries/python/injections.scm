; extends

; based on https://github.com/nvim-treesitter/nvim-treesitter/blob/9d2acd49976e2a9da72949008df03436f781fd23/queries/ecma/injections.scm

;; Support for injecting other syntaxes into Python.
;; Example:
;;
;; class Annotate:
;;     def __getattr__(self, name: str):
;;         def annotate(code: str) -> str:
;;             return code
;;
;;         return annotate
;;
;; annotate = Annotate()
;; js = annotate.js
;;
;; // Normal function call:
;; js("console.log('hello world')")
;;
;; // Method call:
;; annotate.js("console.log('hello world')")

; javascript("..."), typescript("""..."""), etc.
(call
  function: (identifier) @injection.language
  arguments: (argument_list
    (string) @injection.content)
  (#match? @injection.language "^[a-zA-Z][a-zA-Z0-9]*$")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  ; Languages excluded from auto-injection due to special rules
  ; - svg uses the html parser
  (#not-any-of? @injection.language "svg"))

; obj.lang("..."), obj.lang("""..."""), etc.
(call
  function: (attribute
    object: (identifier)
    attribute: (identifier) @injection.language)
	arguments: (argument_list
    (string) @injection.content)
  (#match? @injection.language "^[a-zA-Z][a-zA-Z0-9]*$")
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  ; Languages excluded from auto-injection due to special rules
  ; - svg uses the html parser
  (#not-any-of? @injection.language "svg"))

; svg("..."), svg("""..."""), etc.
(call
  function: (identifier) @_name
  (#eq? @_name "svg")
  arguments: (argument_list
    (string) @injection.content)
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "html"))

; obj.svg("..."), obj.svg("""..."""), etc.
(call
  function: (attribute
    object: (identifier)
    attribute: (identifier) @_name)
	(#eq? @_name "svg")
	arguments: (argument_list
    (string) @injection.content)
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "html"))

