var palette = [
  { name: "blue", value: "#5b9cff" },
  { name: "cyan", value: "#45c7d9" },
  { name: "green", value: "#6ac889" },
  { name: "amber", value: "#e6bc5c" },
  { name: "orange", value: "#ed9863" },
  { name: "purple", value: "#ad8df0" },
  { name: "pink", value: "#e68fba" },
  { name: "red", value: "#e77b78" }
]

function value(name) {
  for (var i = 0; i < palette.length; i++) {
    if (palette[i].name === name) return palette[i].value
  }
  return palette[0].value
}
