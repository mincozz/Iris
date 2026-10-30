.pragma library

// What the companion says. Local only: nothing here is sent to a model.
// The window class is only used to pick a category, titles are never read.

function pick(list) { return list[Math.floor(Math.random() * list.length)] }

var CATEGORIES = [
    ["terminal", /kitty|alacritty|foot|wezterm|konsole|ghostty|xterm|terminal/],
    ["code",     /^code|codium|zed|jetbrains|idea|pycharm|clion|webstorm|nvim|neovide|cursor|sublime/],
    ["browser",  /firefox|chrom|brave|zen|vivaldi|librewolf|epiphany/],
    ["chat",     /discord|vesktop|slack|teams|telegram|signal|element|whatsapp|thunderbird/],
    ["music",    /spotify|rhythmbox|deezer|amberol|lollypop/],
    ["video",    /mpv|vlc|celluloid|totem|obs/],
    ["files",    /nautilus|dolphin|thunar|nemo|yazi|pcmanfm/],
    ["doc",      /libreoffice|obsidian|notion|evince|okular|zathura|onlyoffice|calc|writer/],
    ["game",     /steam|lutris|heroic|minecraft|game/]
]

function category(cls) {
    const c = (cls || "").toLowerCase()
    for (const e of CATEGORIES) if (e[1].test(c)) return e[0]
    return "other"
}

var FOCUS = {
    terminal: ["Au boulot !", "Ça sent la ligne de commande.", "sudo make me a sandwich", "Un petit git status ?"],
    code:     ["On code ?", "Pense à commit !", "Les bugs n'ont qu'à bien se tenir.", "Hmm, ça compile ?"],
    browser:  ["Tu cherches quoi ?", "Attention aux onglets, ils se multiplient.", "Internet, hein..."],
    chat:     ["Des nouvelles des copains ?", "Dis bonjour de ma part !", "Bavarde pas trop longtemps."],
    music:    ["Ça groove ♪", "Oh, de la musique !", "♪ la la la ♪"],
    video:    ["Séance cinéma !", "Je peux avoir du popcorn ?"],
    files:    ["Le rangement, j'adore !", "On trie quoi ?"],
    doc:      ["Studieux, tout ça.", "Je te regarde bosser.", "Un petit café ?"],
    game:     ["On joue ?! Je veux jouer !", "Ne t'énerve pas !"],
    other:    ["Hop, nouvelle fenêtre.", "Coucou !"]
}
function focus(cat) { return pick(FOCUS[cat] || FOCUS.other) }

var OPENED = {
    terminal: ["Un nouveau terminal ! On code ?", "Ooh, un terminal !"],
    browser:  ["Une fenêtre web !", "On surfe ?"],
    code:     ["L'éditeur est de sortie !"],
    game:     ["Un jeu ?! Je viens !"],
    other:    ["Oh, une nouvelle fenêtre !", "Ça s'ouvre !", "Coucou la nouvelle !"]
}
function opened(cat) { return pick(OPENED[cat] || OPENED.other) }

var CLOSED = ["Bye bye fenêtre.", "Pouf, disparue.", "Elle n'est plus là..."]
function closed() { return pick(CLOSED) }

var MANY = ["Ça fait beaucoup de fenêtres, non ?", "Ton bureau commence à déborder !"]
function many() { return pick(MANY) }

var PET = ["hihi", "Oh oui, encore !", "♥", "Tu es gentil.", "Ronron~"]
function pet() { return pick(PET) }

var GRABBED = ["Eh ! Repose-moi !", "Aaah, je vole !", "Ouh, ça tourne !"]
function grabbed() { return pick(GRABBED) }

function idle(hour) {
    if (hour >= 0 && hour < 5)   return pick(["Il est très tard... va dormir.", "Les noctambules, c'est toi !"])
    if (hour >= 5 && hour < 9)   return pick(["Bonjour ! Bien dormi ?", "Un café pour démarrer ?"])
    if (hour >= 12 && hour < 14) return pick(["C'est l'heure de manger ?", "Une pause déj, ça te dit ?"])
    if (hour >= 22)              return pick(["Il se fait tard...", "Encore un peu ? Pas trop longtemps."])
    return pick(["Pense à t'hydrater !", "Un petit étirement ?", "Je suis là si tu as besoin.", "Coucou !", "Tu tiens le coup ?"])
}
