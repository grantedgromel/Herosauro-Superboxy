class_name StoryData
extends RefCounted
## The book, as data. Every chapter's pages, in the original European
## Portuguese and an English translation, plus what the level asks of the
## player. Shared read-only data, like PhysicsLayers: any stream may read it,
## only the lead edits it. The Portuguese of chapters "adamastor" and "dragao"
## is the book's text verbatim (docs/story/SOURCE.md). Chapter "pandas" is an
## adaptation written from the series outline, because the book's own words
## for it are baked into page images that are not in this repository; it is
## flagged `adapted` so nobody mistakes it for the original.
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
				"pt": "— Direita! — gritou Kiko, lançando o primeiro murro! — Esquerda! — exclamou, movendo-se rápido como o vento!",
				"en": "\"Right!\" shouted Kiko, throwing the first punch! \"Left!\" he cried, moving as fast as the wind!"},
			{"id": "a07", "art": "res://assets/story/adamastor/a07.webp",
				"pt": "Kiko, embora mais novo, não teve medo. \"Boxy boxy!\", gritou ele, pronto para a ação.",
				"en": "Kiko was the younger one, but he wasn't scared. \"Boxy boxy!\" he shouted, ready for action."},
			{"id": "a08", "art": "res://assets/story/adamastor/a08.webp",
				"pt": "Os dois irmãos voaram à velocidade da luz até à Ponte de D. Luís. O Adamastor estava a abanar a ponte com as suas mãos gigantes: — Esta cidade é minha!",
				"en": "The two brothers flew at the speed of light to the Dom Luís Bridge. Adamastor was shaking the bridge with his giant hands: \"This city is mine!\""},
		],
		## Shown by the HUD during the fight, never blocking play. `when` is a
		## trigger the HUD understands: "start" (a few seconds in), "phase2"
		## (the boss crosses half health), "low" (boss under 20%).
		"beats": [
			{"id": "a09", "when": "start",
				"pt": "— Não vais destruir a nossa ponte! Rui ergueu as mãos e, num brilho verde, surgiu um T-Rex de energia pura: RROOAAARRR!",
				"en": "\"You won't wreck our bridge!\" Rui raised his hands and, in a green flash, a T-Rex of pure energy appeared: RROOAAARRR!"},
			{"id": "a11", "when": "phase2",
				"pt": "Enquanto o gigante estava ocupado com o dinossauro, Kiko voou à volta da sua cabeça com os seus rápidos movimentos de \"boxy boxy\".",
				"en": "While the giant was busy with the dinosaur, Kiko flew around his head with his speedy \"boxy boxy\" moves."},
			{"id": "a12", "when": "low",
				"pt": "— Agora, Kiko! — gritou Rui. Juntos, os dois irmãos deram o golpe final!",
				"en": "\"Now, Kiko!\" shouted Rui. Together, the two brothers landed the final blow!"},
		],
		"outro": [
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
				"pt": "O Porto dorme sob a lua cheia. Uma carrinha avança pelas ruas silenciosas. Lá dentro, um grupo de duendes ri e aponta. Esta noite, eles não vieram para brincar.",
				"en": "Porto sleeps under the full moon. A van creeps through the silent streets. Inside, a gang of goblins giggles and points. Tonight, they haven't come to play."},
			{"id": "d02", "art": "res://assets/story/dragao/d02.webp",
				"pt": "Eles chegam ao estádio do Porto. O duende-chefe olha pela janela e sorri. Ele sonha com as taças brilhantes lá dentro. Os duendes não têm nenhuma taça própria.",
				"en": "They arrive at Porto's stadium. The goblin chief peers through the window and grins. He dreams of the shiny cups inside. The goblins don't have a single cup of their own."},
			{"id": "d03", "art": "res://assets/story/dragao/d03.webp",
				"pt": "Os duendes entram na sala das taças. Eles veem copas grandes, brilhantes e bonitas. \"São melhores do que as nossas!\", dizem a rir. Com cuidado, começam a roubá-las todas.",
				"en": "The goblins sneak into the trophy room. They see big, shiny, beautiful cups. \"They're better than ours!\" they laugh. Carefully, they start stealing every one."},
			{"id": "d04", "art": "res://assets/story/dragao/d04.webp",
				"pt": "No relvado, o dragão azul dorme tranquilo. Ele é o guardião do estádio. Os duendes aproximam-se devagar, sem fazer barulho. Eles têm planos travessos para o atacar.",
				"en": "On the pitch, the blue dragon sleeps peacefully. He is the guardian of the stadium. The goblins tiptoe closer without a sound. They have a naughty plan to catch him."},
			{"id": "d05", "art": "res://assets/story/dragao/d05.webp",
				"pt": "O dragão acorda e luta com coragem. Ele ruge e tenta afastar os duendes. Mas são muitos. Eles cercam-no e prendem-no com cordas.",
				"en": "The dragon wakes up and bravely fights back. He roars and tries to shoo the goblins away. But there are too many. They surround him and tie him up with ropes."},
			{"id": "d06", "art": "res://assets/story/dragao/d06.webp",
				"pt": "No escritório, o presidente vê tudo pela janela. O dragão azul está cercado e preso. Os duendes levam as taças num saco. Assustado, ele liga: \"Ajuda! Chamem o Herosauro e o Super Boxy!\"",
				"en": "In his office, the president sees it all through the window. The blue dragon is surrounded and tied up. The goblins carry the cups off in a sack. Frightened, he calls: \"Help! Call Herosauro and Super Boxy!\""},
			{"id": "d07", "art": "res://assets/story/dragao/d07.webp",
				"pt": "Em casa, o Rui e o Kiko olham pela janela. No céu, surgem dois sinais brilhantes. Um dinossauro e uma luva de boxe. A cidade chama pelo Herosauro e pelo Super Boxy!",
				"en": "At home, Rui and Kiko look out of the window. Two bright signals light up the sky: a dinosaur and a boxing glove. The city is calling Herosauro and Super Boxy!"},
			{"id": "d08", "art": "res://assets/story/dragao/d08.webp",
				"pt": "O Herosauro e o Super Boxy voam alto no céu! As capas abrem-se como asas. Lá em baixo, a cidade brilha. Eles seguem rápidos para o estádio.",
				"en": "Herosauro and Super Boxy soar high into the sky! Their capes spread like wings. Below them, the city twinkles. They race to the stadium."},
		],
		"beats": [
			{"id": "d09", "when": "start",
				"pt": "Eles aterram com força no meio do estádio! Assustados, os duendes fogem a correr.",
				"en": "They land with a BOOM in the middle of the stadium! The startled goblins scatter."},
			{"id": "d10", "when": "stage2",
				"pt": "O Super Boxy pega numa bola. PUMBA! A bola acerta nos duendes, um a um. Eles voam para todos os lados!",
				"en": "Super Boxy grabs a ball. WHAM! The ball knocks over the goblins, one by one. They go flying everywhere!"},
		],
		"outro": [
			{"id": "d11", "art": "res://assets/story/dragao/d11.webp",
				"pt": "Os duendes correm para a carrinha. Querem fugir depressa. O dragão sopra fogo quente! A carrinha queima e eles param.",
				"en": "The goblins run for their van. They want to get away fast. The dragon breathes hot fire! The van goes up in smoke and they stop in their tracks."},
			{"id": "d12", "art": "res://assets/story/dragao/d12.webp",
				"pt": "\"Eles cheiram mal!\", diz o Herosauro. \"Levem-nos até ao rio! Está na hora de um bom banho!\" Os pterodáctilos agarram nos duendes e levantam voo.",
				"en": "\"They're stinky!\" says Herosauro. \"Take them to the river! It's bath time!\" The pterodactyls scoop up the goblins and take off."},
			{"id": "d13", "art": "res://assets/story/dragao/d13.webp",
				"pt": "Os pterodáctilos chegam ao rio Douro. Um a um, largam os duendes na água. Eles caem com grandes salpicos. O rio leva-os a flutuar para longe da cidade.",
				"en": "The pterodactyls reach the Douro. One by one, they drop the goblins into the water. SPLASH! SPLASH! The river floats them far away from the city."},
			{"id": "d14", "art": "res://assets/story/dragao/d14.webp",
				"pt": "\"Obrigado!\", diz o presidente com um sorriso. O dragão está seguro outra vez. As taças voltam ao seu lugar. O Herosauro e o Super Boxy salvaram o tesouro do Dragão!",
				"en": "\"Thank you!\" says the president with a smile. The dragon is safe again. The cups are back in their place. Herosauro and Super Boxy saved the Dragon's treasure!"},
		],
	},
	"pandas": {
		"number": 3,
		"title": {"pt": "Os Turistas Panda", "en": "The Panda Tourists"},
		"tagline": {"pt": "Faz uma cidade mágica para os pandas!", "en": "Build a magical town for the pandas!"},
		"cover": "res://assets/story/pandas/cover.webp",
		"accent": Color(0.93, 0.55, 0.20),
		"objective": {"pt": "Repara as casas para os pandas!", "en": "Fix up the houses for the pandas!"},
		"adapted": true,
		"intro": [
			{"id": "p01", "art": "res://assets/story/pandas/p01.webp",
				"pt": "Numa manhã de sol, chega ao Porto uma família de pandas: o Pai Panda, a Mãe Panda e os dois filhos. Vêm de muito longe para conhecer a cidade.",
				"en": "One sunny morning, a family of pandas arrives in Porto: Daddy Panda, Mummy Panda and their two children. They have come from far away to see the city."},
			{"id": "p02", "art": "res://assets/story/pandas/p02.webp",
				"pt": "Passeiam pela Ribeira, veem os barcos no rio e provam pastéis de nata. \"Que cidade tão bonita!\", diz a Mãe Panda.",
				"en": "They stroll along the Ribeira, watch the boats on the river and taste pastéis de nata. \"What a beautiful city!\" says Mummy Panda."},
			{"id": "p03", "art": "res://assets/story/pandas/p03.webp",
				"pt": "Ao fim do dia, procuram um sítio para dormir. Mas os hotéis estão todos cheios! \"Não há lugar para nós\", diz o Pai Panda, muito triste.",
				"en": "At the end of the day, they look for somewhere to sleep. But every hotel is full! \"There's no room for us,\" says Daddy Panda, very sadly."},
			{"id": "p04", "art": "res://assets/story/pandas/p04.webp",
				"pt": "A pequena panda boceja. O irmão abraça a mala. Está a ficar escuro e a família não tem para onde ir.",
				"en": "The little panda yawns. Her brother hugs his suitcase. It's getting dark, and the family has nowhere to go."},
			{"id": "p05", "art": "res://assets/story/pandas/p05.webp",
				"pt": "Da janela de casa, o Rui e o Kiko veem tudo. \"Temos de ajudar!\", diz o Kiko. \"Isto é um trabalho para o Herosauro e o Super Boxy!\"",
				"en": "From their window at home, Rui and Kiko see everything. \"We have to help!\" says Kiko. \"This is a job for Herosauro and Super Boxy!\""},
			{"id": "p06", "art": "res://assets/story/pandas/p06.webp",
				"pt": "Os heróis levam os pandas a uma rua velha e esquecida. As casas estão partidas e há lixo por todo o lado. \"Aqui?\", pergunta o Pai Panda. \"Esperem e vão ver!\", diz o Herosauro.",
				"en": "The heroes lead the pandas to an old, forgotten street. The houses are broken and there's rubbish everywhere. \"Here?\" asks Daddy Panda. \"Just wait and see!\" says Herosauro."},
		],
		"beats": [
			{"id": "p07", "when": "start",
				"pt": "Com a força do T-Rex e os murros do Super Boxy, a rua velha começa a mudar…",
				"en": "With the power of the T-Rex and Super Boxy's punches, the old street begins to change…"},
			{"id": "p08", "when": "half",
				"pt": "As casas ganham cor, azulejos novos e flores nas varandas! Os pandas batem palmas.",
				"en": "The houses fill with colour, new tiles and flowers on the balconies! The pandas clap their paws."},
		],
		"outro": [
			{"id": "p09", "art": "res://assets/story/pandas/p09.webp",
				"pt": "Com um último brilho verde, a rua velha transforma-se numa cidade mágica! Há luzes a brilhar, música e uma casa novinha para os pandas.",
				"en": "With one last green sparkle, the old street turns into a magical town! There are twinkling lights, music, and a brand-new house for the pandas."},
			{"id": "p10", "art": "res://assets/story/pandas/p10.webp",
				"pt": "\"É a casa mais bonita do mundo!\", diz a pequena panda. Nessa noite, todos jantam juntos na praça, entre gelados e gargalhadas.",
				"en": "\"It's the most beautiful house in the world!\" says the little panda. That night, everyone has dinner together in the square, with ice cream and lots of giggles."},
			{"id": "p11", "art": "res://assets/story/pandas/p11.webp",
				"pt": "O Herosauro e o Super Boxy sorriem. No Porto, há sempre lugar para todos. Mais uma vez, salvaram o dia, juntos!",
				"en": "Herosauro and Super Boxy smile. In Porto, there's always room for everyone. Once again, they saved the day, together!"},
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
