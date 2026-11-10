-- Puts every paragraph that opens with "*Breaks as:*" in a call-out box.
-- The box is the breaksbox environment in guide-header.tex.

function Para(el)
  local first = el.content[1]
  if first and first.t == "Emph"
      and pandoc.utils.stringify(first):match("^Breaks as:") then
    return {
      pandoc.RawBlock("latex", "\\begin{breaksbox}"),
      el,
      pandoc.RawBlock("latex", "\\end{breaksbox}"),
    }
  end
end
