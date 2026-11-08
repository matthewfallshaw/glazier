stds.hs = {
  globals = {
    hs = {
      other_fields = true,
    },
  },
}
std = 'max+hs'
ignore = { '614' }
files["spec"] = { std = "+busted" }
max_comment_line_length = false  -- Hammerspoon doc comments are one line per paragraph
