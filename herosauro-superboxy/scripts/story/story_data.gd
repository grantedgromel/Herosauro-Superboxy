class_name StoryData
extends RefCounted
## The book, as data. Every chapter's pages, in the original European
## Portuguese and an English translation, plus what the level asks of the
## player. Shared read-only data, like PhysicsLayers: any stream may read it,
## only the lead edits it. The Portuguese is the owner's final book text
## ("As Aventuras de Herosauro & Super Boxy", reformatted edition), with only
## spelling slips corrected (docs/story/SOURCE.md lists them). In-game beats
## are short spoken excerpts of a page, not whole pages.
##
## Page ids follow the book: the letter is the story, the number is the page
## within that story, which is also the number on the owner's Drive picture
## (e.g. d05 is "#5.png" in the Estádio do Dragão folder).
##
## A page's `art` is a path that may not exist yet. The book's illustrations
## live in the owner's Drive; when a page image is dropped at that path the
## reader shows it, and until then the reader composes the page from the art
## that is committed. `voice` likewise names an optional recorded narration
## file per language, which overrides text-to-speech when present.
##
## Page ids are stable: art and narration files are keyed by them.

const LANGS := ["pt", "en"]
const DEFAULT_LANG := "pt"

const ORDER := ["adamastor", "dragao", "pandas"]

const CHAPTERS := {
	"adamastor": {
		"number": 1,
		"title": {"pt": "O Gigante do Douro", "en": "The Giant of the Douro"},
		"tagline": {"pt": "Salva as pontes do Porto!", "en": "Save the bridges of Porto!"},
		"cover": "res://assets/ui/key_art.png",
		"accent": Color(0.20, 0.62, 0.34),
		"objective": {"pt": "Derrota o Adamastor!", "en": "Stop Adamastor!"},
		"adapted": false,
		"intro": [
			{"id": "a01", "art": "res://assets/story/adamastor/a01.webp",
				"pt": "Na colorida cidade do Porto, viviam dois irmãos, Rui e Kiko. Para o mundo, eram apenas dois meninos comuns… mas entre eles… tinham um segredo poderoso.",
				"en": "In the colourful city of Porto lived two brothers, Rui and Kiko. To the world they were just two ordinary boys… but between them… they shared a powerful secret."},
			{"id": "a02", "art": "res://assets/story/adamastor/a02.webp",
				"pt": "Quando o perigo chamava, eles transformavam-se nos super-heróis mais corajosos da cidade. Rui, o poderoso Herosauro, e Kiko, o mais valente Super Boxy — os heróis do Porto!",
				"en": "Whenever danger called, they turned into the bravest superheroes in the city. Rui, the mighty Herosauro, and Kiko, the bravest Super Boxy — the heroes of Porto!"},
			{"id": "a03", "art": "res://assets/story/adamastor/a03.webp",
				"pt": "Um dia, ouviu-se um barulho enorme vindo do rio Douro. Era o terrível Adamastor, o gigante dos mares! Ele saiu da água, com os olhos muito zangados, pronto para destruir a cidade!",
				"en": "One day, an enormous noise came from the Douro river. It was the terrible Adamastor, the giant of the seas! He rose out of the water with very angry eyes, ready to wreck the city!"},
			{"id": "a04", "art": "res://assets/story/adamastor/a04.webp",
				"pt": "CRASH! O Adamastor começou a atacar as pontes do rio Douro! — Isto é um trabalho para o Herosauro e o Super Boxy! Vamos, Kiko! A cidade precisa de nós! — gritou Rui.",
				"en": "CRASH! Adamastor began to attack the bridges over the Douro! \"This is a job for Herosauro and Super Boxy! Come on, Kiko! The city needs us!\" shouted Rui."},
			{"id": "a05", "art": "res://assets/story/adamastor/a05.webp",
				"pt": "— Esquerda! — exclamou, movendo-se rápido como o vento!",
				"en": "\"Left!\" he cried, moving as fast as the wind!"},
			{"id": "a06", "art": "res://assets/story/adamastor/a06.webp",
				"pt": "— Direita! — gritou Kiko, lançando o primeiro murro!",
				"en": "\"Right!\" shouted Kiko, throwing the first punch!"},
			{"id": "a07", "art": "res://assets/story/adamastor/a07.webp",
				"pt": "Kiko, embora mais novo, não teve medo. \"Boxy boxy!\", gritou ele, pronto para a ação.",
				"en": "Kiko was the younger one, but he wasn't scared. \"Boxy boxy!\" he shouted, ready for action."},
			{"id": "a08", "art": "res://assets/story/adamastor/a08.webp",
				"pt": "Os dois irmãos voaram à velocidade da luz até à Ponte de D. Luís. O Adamastor estava a abanar a ponte com as suas mãos gigantes, expressando a sua destruição: — Esta cidade é minha!",
				"en": "The two brothers flew at the speed of light to the Dom Luís Bridge. Adamastor was shaking the bridge with his giant hands, roaring about the damage he would do: \"This city is mine!\""},
		],
		## Shown by the HUD during play, never blocking it, and kept short because
		## they are spoken over the action. `when` is a trigger the HUD understands:
		## "start" (a few seconds in), "phase2" (the boss crosses half health), "low"
		## (boss under 20%); a level may also request a beat by id.
		"beats": [
			{"id": "a09", "when": "start",
				"pt": "— Não vais destruir a nossa ponte! RROOAAARRR! Surgiu o T-Rex de energia!",
				"en": "\"You won't wreck our bridge!\" RROOAAARRR! The energy T-Rex appears!"},
			{"id": "a11", "when": "phase2",
				"pt": "O T-Rex morde o braço do gigante, e o Kiko voa à volta da cabeça: boxy boxy!",
				"en": "The T-Rex bites the giant's arm, and Kiko zooms round his head: boxy boxy!"},
			{"id": "a12", "when": "low",
				"pt": "— Agora, Kiko! — gritou Rui. Um soco boxy boxy no queixo do gigante!",
				"en": "\"Now, Kiko!\" shouted Rui. A boxy boxy punch right on the giant's chin!"},
		],
		"outro": [
			{"id": "a13", "art": "res://assets/story/adamastor/a13.webp",
				"pt": "Juntos, os dois irmãos deram o golpe final.",
				"en": "Together, the two brothers landed the final blow."},
			{"id": "a14", "art": "res://assets/story/adamastor/a14.webp",
				"pt": "O soco foi tão forte que o Adamastor perdeu o equilíbrio e caiu de volta no rio Douro com um \"SPLASH\" monumental!",
				"en": "The punch was so strong that Adamastor lost his balance and fell back into the Douro with a gigantic \"SPLASH\"!"},
			{"id": "a15", "art": "res://assets/story/adamastor/a15.webp",
				"pt": "Os céus da cidade do Porto voltaram a brilhar. Herosauro e Super Boxy sorriram — tinham salvado o dia, juntos, mais uma vez!",
				"en": "The skies over Porto shone again. Herosauro and Super Boxy smiled — they had saved the day, together, once again!"},
		],
	},
	"dragao": {
		"number": 2,
		"title": {"pt": "O Tesouro do Dragão", "en": "The Dragon's Treasure"},
		"tagline": {"pt": "Recupera as taças do estádio!", "en": "Win back the stadium's cups!"},
		"cover": "res://assets/story/dragao/cover.webp",
		"accent": Color(0.13, 0.36, 0.78),
		"objective": {"pt": "Liberta o dragão e recupera as taças!", "en": "Free the dragon and win back the cups!"},
		"adapted": false,
		"intro": [
			{"id": "d01", "art": "res://assets/story/dragao/d01.webp",
				"pt": "Numa noite de lua cheia, a cidade do Porto dormia tranquila. Mas nem todos dormiam. Vindos das terras do sul, um grupo de duendes malandros preparava um golpe terrível.",
				"en": "On a full-moon night, the city of Porto was sleeping peacefully. But not everyone was asleep. Driving up from the lands of the south, a gang of naughty goblins was planning a terrible trick."},
			{"id": "d02", "art": "res://assets/story/dragao/d02.webp",
				"pt": "O chefe dos duendes desde sempre desejava para ele todas as taças do incrível FC Porto. E, com um sorriso maléfico, confirma: \"Vamos roubar os tesouros do Dragão!\"",
				"en": "The goblin chief had always wanted every one of the amazing FC Porto's cups for himself. And with a wicked grin he says: \"Let's steal the Dragon's treasures!\""},
			{"id": "d03", "art": "res://assets/story/dragao/d03.webp",
				"pt": "Silenciosos como ratinhos, os duendes entraram na sala dos troféus, preparados para roubar. \"Uau! Estas taças são maiores, mais brilhantes e muito mais bonitas do que as nossas!\"",
				"en": "Quiet as little mice, the goblins crept into the trophy room, ready to steal. \"Wow! These cups are bigger, shinier and much prettier than ours!\""},
			{"id": "d04", "art": "res://assets/story/dragao/d04.webp",
				"pt": "Os duendes, quando atravessavam o estádio para fugir, repararam no grande Dragão que dormia profundamente. \"Vamos levar o dragão também!\", riram, aproximando-se devagar.",
				"en": "As the goblins crossed the stadium to get away, they spotted the great Dragon, fast asleep. \"Let's take the dragon too!\" they giggled, creeping closer."},
			{"id": "d05", "art": "res://assets/story/dragao/d05.webp",
				"pt": "De repente, cordas voavam no ar! O Dragão acordou num sobressalto… Mas já era tarde demais. Estava cercado de duendes.",
				"en": "Suddenly, ropes went flying through the air! The Dragon woke with a start… but it was too late. He was surrounded by goblins."},
			{"id": "d06", "art": "res://assets/story/dragao/d06.webp",
				"pt": "Do seu camarote, o presidente do Porto viu tudo e, com rapidez, pegou no telefone e disse, aflito: \"Socorro! Chamem o Herosauro e o Super Boxy! O Draco precisa de ajuda!\"",
				"en": "From his box, the president of Porto saw everything. Quickly he picked up the phone and cried: \"Help! Call Herosauro and Super Boxy! Draco needs help!\""},
			{"id": "d07", "art": "res://assets/story/dragao/d07.webp",
				"pt": "Em casa, Rui e Kiko preparavam-se para ir dormir quando o céu se iluminou. E os dois irmãos disseram ao mesmo tempo: \"A cidade precisa de nós!\"",
				"en": "At home, Rui and Kiko were getting ready for bed when the sky lit up. And the two brothers said at the same time: \"The city needs us!\""},
			{"id": "d08", "art": "res://assets/story/dragao/d08.webp",
				"pt": "Num instante, transformaram-se! Herosauro e Super Boxy voaram à velocidade da luz, em direção ao Estádio do Dragão, prontos para salvar o amigo Draco.",
				"en": "In a flash, they transformed! Herosauro and Super Boxy flew at the speed of light towards the Estádio do Dragão, ready to rescue their friend Draco."},
		],
		"beats": [
			{"id": "d09", "when": "start",
				"pt": "BOOM! Os heróis aterram no estádio! Os duendes fogem em pânico.",
				"en": "BOOM! The heroes land in the stadium! The goblins run off in a panic."},
			{"id": "d10", "when": "stage2",
				"pt": "PUMBA! O Super Boxy chuta a bola contra os duendes!",
				"en": "WHAM! Super Boxy kicks the ball at the goblins!"},
		],
		"outro": [
			{"id": "d11", "art": "res://assets/story/dragao/d11.webp",
				"pt": "Tentando fugir, os duendes da camisola vermelha correram para o carro. Mas o Dragão, solto das suas amarras, cuspiu fogo e transformou o carro num bloco de carvão.",
				"en": "Trying to escape, the goblins in red shirts ran for their car. But the Dragon, free of his ropes, breathed fire and turned the car into a lump of coal."},
			{"id": "d12", "art": "res://assets/story/dragao/d12.webp",
				"pt": "\"Estes duendes jogam sempre sujo!\", disse Herosauro. \"Precisam de um banho!\" Os pterodáctilos do Herosauro agarraram os duendes um a um e voaram sobre a cidade iluminada.",
				"en": "\"These goblins always play dirty!\" said Herosauro. \"They need a bath!\" Herosauro's pterodactyls grabbed the goblins one by one and flew over the twinkling city."},
			{"id": "d13", "art": "res://assets/story/dragao/d13.webp",
				"pt": "SPLASH! SPLASH! SPLASH! Os duendes foram atirados ao rio Douro. E agora tinham de nadar até casa. E assim aprenderam uma lição importante… que roubar o Dragão nunca é uma boa ideia.",
				"en": "SPLASH! SPLASH! SPLASH! The goblins were dropped into the Douro. Now they had to swim all the way home. And so they learned an important lesson… stealing from the Dragon is never a good idea."},
			{"id": "d14", "art": "res://assets/story/dragao/d14.webp",
				"pt": "Com o nascer do sol, o Dragão e os seus tesouros estavam salvos. E, para comemorar, o Presidente disse com um grande sorriso: \"Obrigado, Herosauro e Super Boxy! Mais uma vez vocês salvaram o Porto. O próximo jogo é vosso!\"",
				"en": "As the sun came up, the Dragon and his treasures were safe. To celebrate, the President said with a big smile: \"Thank you, Herosauro and Super Boxy! Once again you saved Porto. The next match is yours!\""},
		],
	},
	"pandas": {
		"number": 3,
		"title": {"pt": "Os Turistas Panda", "en": "The Panda Tourists"},
		"tagline": {"pt": "Faz um bairro novo para os pandas!", "en": "Build a new neighbourhood for the pandas!"},
		"cover": "res://assets/story/pandas/cover.webp",
		"accent": Color(0.93, 0.55, 0.20),
		"objective": {"pt": "Repara as casas!", "en": "Fix up the houses!"},
		"adapted": false,
		"intro": [
			{"id": "p01", "art": "res://assets/story/pandas/p01.webp",
				"pt": "Os Bambosa tinham chegado à cidade, super animados e curiosos, prontos para passear e explorar tudo o que o Porto tinha para mostrar. A família caminhava pelas ruas tradicionais, olhando para o rio Douro, debaixo das suas pontes, e para as casas coloridas que enchiam os passeios de calçada portuguesa.",
				"en": "The Bambosa family had arrived in the city, super excited and curious, ready to stroll around and explore everything Porto had to show. They walked through the old streets, looking at the Douro under its bridges and at the colourful houses lining the cobbled pavements."},
			{"id": "p02", "art": "res://assets/story/pandas/p02.webp",
				"pt": "Passearam por parques verdes e praças. Viram estátuas altas e prédios muito antigos. A família estava encantada com a cidade do Porto!",
				"en": "They wandered through green parks and squares. They saw tall statues and very old buildings. The family was enchanted with Porto!"},
			{"id": "p03", "art": "res://assets/story/pandas/p03.webp",
				"pt": "Um cheirinho maravilhoso vinha de um café na esquina, e a família sentou-se a descansar. Queriam experimentar a cozinha portuguesa, e assim foi: o Senhor Bambosa pediu uma francesinha, a Dona Bambosa escolheu o caldo verde e os filhos, como comeram o bacalhau todo, ganharam cada um dois pastéis de nata. Que delícia!",
				"en": "A wonderful smell drifted from a café on the corner, and the family sat down to rest. They wanted to try Portuguese food, and so they did: Mr Bambosa ordered a francesinha, Mrs Bambosa chose caldo verde, and the children ate up all their bacalhau and each won two pastéis de nata. Yum!"},
			{"id": "p04", "art": "res://assets/story/pandas/p04.webp",
				"pt": "Quando o sol começou a descer, os pandas ficaram cansados. Procuraram um lugar para dormir, mas estava tudo ocupado na cidade. E ninguém tinha tempo para os ajudar. A família começou a ficar preocupada.",
				"en": "When the sun began to set, the pandas grew tired. They looked for somewhere to sleep, but everywhere in the city was full. And nobody had time to help them. The family began to worry."},
			{"id": "p05", "art": "res://assets/story/pandas/p05.webp",
				"pt": "Já quase sem esperança, chegaram ao famoso hotel Vitória's Terrace. A Mãe Rita abriu a porta e sorriu. \"Bem-vindos!\", disse com carinho. Os pandas sentiram-se um pouco melhor.",
				"en": "Almost out of hope, they reached the famous Vitória's Terrace hotel. Mum Rita opened the door and smiled. \"Welcome!\" she said warmly. The pandas felt a little better."},
			{"id": "p06", "art": "res://assets/story/pandas/p06.webp",
				"pt": "A Mãe Rita olhou para o tablet com atenção e, infelizmente, o hotel estava cheio. \"Como vamos ajudar esta família tão querida?\", pensou em silêncio. Mas todos os quartos estavam ocupados.",
				"en": "Mum Rita looked carefully at her tablet and, sadly, the hotel was full. \"How can we help this lovely family?\" she wondered quietly. But every room was taken."},
			{"id": "p07", "art": "res://assets/story/pandas/p07.webp",
				"pt": "A Mãe Rita, muito triste, teve de dizer à família que não havia espaço. O Senhor Bambosa engoliu em seco, olhando para os seus filhos. \"Os meus bebés vão ter de dormir na rua?\", perguntou, assustado, com os olhos cheios de lágrimas. Mas nada se podia fazer.",
				"en": "Very sadly, Mum Rita had to tell the family there was no room. Mr Bambosa gulped, looking at his children. \"Will my babies have to sleep in the street?\" he asked, frightened, his eyes full of tears. But nothing could be done."},
			{"id": "p08", "art": "res://assets/story/pandas/p08.webp",
				"pt": "A Mãe Rita tentou mais uma ideia: telefonou ao Pai Rui e pediu-lhe que procurasse ajuda no bairro, para ver se algum vizinho tinha um quarto disponível. Mas as casas estavam velhas, vazias e estragadas. Ninguém mais morava ali. O Pai Rui voltou triste e cansado.",
				"en": "Mum Rita tried one more idea: she phoned Dad Rui and asked him to look for help in the neighbourhood, in case a neighbour had a spare room. But the houses were old, empty and broken. Nobody lived there any more. Dad Rui came back sad and tired."},
			{"id": "p09", "art": "res://assets/story/pandas/p09.webp",
				"pt": "Mais tarde, enquanto os pais conversavam sobre a Família Bambosa, Rui e Kiko ouviram tudo em silêncio. Olharam um para o outro e souberam logo que não podiam deixar aquela família sem ajuda. E entraram em ação!",
				"en": "Later, while their parents talked about the Bambosa family, Rui and Kiko listened quietly. They looked at each other and knew straight away that they couldn't leave that family without help. And into action they went!"},
			{"id": "p10", "art": "res://assets/story/pandas/p10.webp",
				"pt": "Num instante, transformaram-se! Herosauro e Super Boxy voaram até ao bairro abandonado, prontos para fazer algo especial.",
				"en": "In a flash, they transformed! Herosauro and Super Boxy flew to the abandoned neighbourhood, ready to do something special."},
		],
		"beats": [
			{"id": "p11", "when": "start",
				"pt": "Restaurar o bairro era a ideia! \"Epa!\", disse o Pai, espantado.",
				"en": "Fixing up the neighbourhood was the plan! \"Wow!\" said Dad, amazed."},
			{"id": "p11h", "when": "half",
				"pt": "Com os dinossauros do Herosauro e os materiais do Super Boxy, o bairro muda!",
				"en": "With Herosauro's dinosaurs and Super Boxy's building materials, the street changes!"},
		],
		"outro": [
			{"id": "p12", "art": "res://assets/story/pandas/p12.webp",
				"pt": "Em poucos minutos, o bairro mudou completamente. As ruas estavam seguras, e as casas, novas e limpas. O Pai sorriu orgulhoso. Agora, muitas famílias podiam ficar ali… A Família Bambosa podia ficar ali.",
				"en": "In just a few minutes, the neighbourhood was completely changed. The streets were safe and the houses were new and clean. Dad smiled proudly. Now lots of families could stay there… The Bambosa family could stay there."},
			{"id": "p13", "art": "res://assets/story/pandas/p13.webp",
				"pt": "E, com as boas notícias, a Família Bambosa fez check-in num apartamento maravilhoso. As crianças brincavam no quarto com muita alegria.",
				"en": "And with the good news, the Bambosa family checked into a wonderful apartment. The children played happily in their room."},
			{"id": "p14", "art": "res://assets/story/pandas/p14.webp",
				"pt": "E, na sala ao lado, os pais conversavam, relaxados. Havia comida, risos e agradecimentos. Como verdadeiras férias devem ser. E todos sabiam: ajudar faz o coração crescer.",
				"en": "And in the next room, the parents chatted, relaxed. There was food, laughter and thank-yous. Just as a real holiday should be. And everyone knew: helping makes your heart grow."},
		],
	},
}


static func chapter(id: String) -> Dictionary:
	return CHAPTERS.get(id, {})


static func text(entry: Dictionary, lang: String) -> String:
	if entry.has(lang):
		return entry[lang]
	return entry.get(DEFAULT_LANG, "")


static func next_chapter(id: String) -> String:
	var i := ORDER.find(id)
	if i < 0 or i + 1 >= ORDER.size():
		return ""
	return ORDER[i + 1]
