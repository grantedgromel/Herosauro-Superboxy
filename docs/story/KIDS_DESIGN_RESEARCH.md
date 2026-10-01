# Designing for ages 4 to 8: research notes

KIDS 3D BROWSER GAME RULEBOOK (ages 4-8, co-op, PT-PT/EN picture-book adaptation)

Evidence note: direct page fetch was blocked for most domains (Sesame PDF, NN/g, Game Accessibility Guidelines, Xbox XAG, W3C, Google, FTC, PEGI). Those claims come from search-result excerpts of the cited pages. Only Apple's pages were read in full. Rules tagged [inf] are my design inference, not a quoted source. A browser-only release is not app-store-gated, but Apple/Google Kids rules are the best privacy bar if you ever wrap it.

1. CONTROLS & INPUT
- Movement plus at most 2 buttons (Jump, one context-sensitive Power/Action). Never require holds, combos, or button-mashing. Why: young motor skills; mashing/QTEs are an access barrier. https://gameaccessibilityguidelines.com/avoid-repeated-inputs-button-mashing-quick-time-events/
- Auto-aim and auto-assist on by default, lightly. Mario Kart 8 Deluxe smart steering and auto-accelerate let a 4-year-old race; smart steering is on by default and scales with input. https://www.shacknews.com/article/99831/mario-kart-8-deluxe-adds-accessibility-but-nintendo-has-room-to-grow
- Tap is the easiest gesture. Make drag and tap both work. Avoid pinch, flick-only, tilt and shake; use multi-touch only for non-essential actions. Why: Sesame's 50+ preschooler studies. https://joanganzcooneycenter.org/wp-content/uploads/2020/02/SesameWorkshop-2012.pdf
- Touch targets: hard minimum about 2cm (about 76 CSS px) with generous spacing. Material's 48dp/8dp is the adult floor. Why: NN/g sizing for 3-5 year olds. https://www.nngroup.com/articles/children-ux-physical-development/ and https://developers.google.com/youtube/gaming/playables/certification/best_practices_design
- On-screen layout [inf]: floating joystick (base 140-160px, appears where the left thumb lands, large dead-zone). Action buttons 96px with 16px+ gaps in the bottom corners, 24px from screen edges, nothing important under thumbs. Why: players cannot feel button edges and thumbs hide the view.
- Keyboard [inf]: arrow keys plus Space plus one other key; WASD optional and remappable. Support the Gamepad API. Why: arrows are the easiest keyboard movement for kids; alternative inputs must give equal function. https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/107
- Camera: auto-follow with auto-pivot; manual camera optional and never required. Why: 3D platformers automate the camera so players focus on platforming; a second stick is too much for 4-year-olds [inf]. https://www.gamedeveloper.com/design/camera-evolution-in-third-person-games
- Unlock audio on the first tap ("Toca para comecar"). Why: Chrome blocks audio before a user gesture. https://developer.chrome.com/blog/web-audio-autoplay

2. FAILURE & DIFFICULTY
- No game over, no lives, no timers. A fall or hit sends a bubble to the last safe ground, and health regenerates when standing still. Why: Odyssey Assist Mode. https://smo.wiki/Assist_Mode
- Respawn in under 2 s; checkpoints every 10-15 s of play and before every set-piece [inf]. Why: LEGO games have no game overs and falling respawns immediately. https://gameinformer.com/b/features/archive/2013/01/14/ready-player-2-traveller-39-s-tales-and-co-op
- Drop-in/drop-out co-op: player 2 joins with one key or tap at any time, and AI plays the second brother when solo. Why: LEGO co-op model. https://gameinformer.com/b/features/archive/2013/01/14/ready-player-2-traveller-39-s-tales-and-co-op
- Give the weaker player an invincible helper role (Cappy in Odyssey, Waddle Dee in Kirby, Nabbit in Mario Wonder). The helper can collect, stun and revive. https://twinfinite.net/news/super-mario-odyssey-2-player-mode-lets-you-control-cappy/ and https://www.shacknews.com/article/136864/super-mario-bros-wonder-playable-characters
- Shared team goals and one collectible counter; no per-player score. Why: co-play research favours experiences that appeal to child and parent together. https://joanganzcooneycenter.org/2025/05/29/playing-well-together/
- Rubber-band the world, not the child: a lagging partner is teleported or bubbled to P1. Add quiet adaptive help (arrows, fewer enemies) after 3 repeated failures. Why: visible rubber-banding feels unfair, but transparent DDA reduces frustration. https://en.wikipedia.org/wiki/Dynamic_game_difficulty_balancing
- Name help neutrally ("Ajudas"/"Assists", never "Easy"). Why: Celeste reworded its Assist text to avoid sounding gatekeepy. https://www.gamedeveloper.com/design/check-out-i-celeste-s-i-remarkably-granular-assist-options

3. FEEDBACK & JUICE
- Positive-only: a wrong or missed action gives a soft neutral boing plus a visual hint, never a buzzer, red X, or lost reward. Why: Toca Boca's no-win/no-lose play keeps kids relaxed. https://screenwiseapp.com/guides/the-parents-guide-to-toca-boca-games-why-theyre-the-gold-standard
- Characters greet and guide; instructions state the objective plus how; use audio to flag what matters. Why: Sesame preschool best practice. https://joanganzcooneycenter.org/wp-content/uploads/2020/02/SesameWorkshop-2012.pdf
- Collectibles only accumulate and never spill on hits [inf]. Why: avoids punishing loss for 4-6 year olds.
- Idle hint ladder: subtle visual cue after about 4 s, stronger cue plus voice after about 8 s. Why: timed hints rescue stuck players. https://create.roblox.com/docs/production/game-design/onboarding-techniques
- Juice (squash/stretch, sparkle, cheer) is welcome but must stay inside the flash limits in section 6.

4. READING & NARRATION
- Everything a child must understand is spoken; text is optional support. Voice every prompt, including the parental gate. https://developer.apple.com/kids/
- Use real PT-PT voice recording or pre-generated neural audio (Azure pt-PT-Raquel/Duarte/Fernanda). Why: browser speechSynthesis varies by OS, loads voices asynchronously, and Chrome cuts long utterances. https://readium.org/speech/docs/WebSpeech.html, https://www.testmuai.com/learning-hub/speech-synthesis-api-browser-support/ and https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support
- Word-by-word read-along highlight synced to narration. Why: it links print to speech and improved word reading. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4014672/
- Icon-first UI with recognisable images, not text menus. Why: PBS KIDS design approach. https://www.educatorstechnology.com/2026/09/pbs-kids-games-review.html
- Language toggle: native names ("Portugues"/"English") plus a globe icon, never flags. Default PT-PT, switch live, keep chapter state, set the lang attribute. Why: flags are countries, not languages. https://simplelocalize.io/blog/posts/flags-as-language-in-language-selector/
- Story hotspots: few, tied to the story moment. Why: too many distract from the narrative. https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2020.593482/full

5. SESSION, PACING, STORY FRAME
- Chapters of 6-10 min ending at a natural stopping point, with autosave at checkpoints and "continue" on return [inf]. Why: preschool attention spans run roughly 3-10 min. https://bluebirddayprogram.com/honoring-a-preschoolers-attention-span/
- Total play: WHO/AAP suggest about 1 hour/day of high-quality media for ages 2-5, with co-viewing. Offer a parent-set gentle "time to rest" prompt; no streaks or guilt. https://publications.aap.org/pediatrics/article/138/5/e20162591/60503/Media-and-Young-Minds and https://www.nbcnews.com/health/kids-health/no-screen-time-babies-only-1-hour-kids-under-5-n998051
- Page-turn cutscenes [inf]: use the book's illustrations, 15-25 s, voiced with highlighted text, tap to advance or skip.
- Reward between chapters: unlock the next illustrated "page", stickers, costumes. Never daily-login or scarcity rewards. Why: nudge techniques are restricted for children. https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/age-appropriate-design-a-code-of-practice-for-online-services/
- Write co-op moments into story beats (the brothers need each other). Why: joint media engagement supports learning. https://joanganzcooneycenter.org/wp-content/uploads/2011/12/jgc_coviewing_desktop.pdf

6. VISUAL & UI RULES
- Text at least 28px at 1080p for UI and subtitles (aim 32-40). Sans-serif with clear letterforms (Andika, Lexend); picture-book type is 18pt+. https://gameaccessibilityguidelines.com/full-list/ and https://www.taylor.com/blog/a-guide-to-printing-childrens-books
- Contrast 4.5:1 for normal text, 3:1 for large text and key UI. https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/102
- Never colour alone: pair hue with shape/icon and use Okabe-Ito colours (about 8% of men are red-green deficient). Give each brother a distinct silhouette. https://sci-draw.com/blog/colorblind-safe-palettes-okabe-ito-reference
- Flash: no more than 3 per second, flashing area under 25% of a 10-degree field, avoid red flashes. Practical rule: no full-screen flashes at all. https://www.w3.org/WAI/WCAG20/Understanding/three-flashes-or-below-threshold
- XAG 118 treats a 10% luminance change over about 20% of the screen at over 3/s as failing. Ship a Flashing toggle, default reduced. https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/118
- Camera shake, bob and blur: subtle by default, toggle to off, honour prefers-reduced-motion. https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/117

7. CONTENT & SAFETY
- Aim for PEGI 3 / ESRB E: only very mild comic slapstick violence (Tom & Jerry level), wholly fantasy characters, nothing frightening. PEGI 7 adds non-realistic violence and a Fear descriptor. https://pegi.info/what-do-the-labels-mean, https://www.uswitch.com/broadband/studies/parents-guide-to-gaming/ and https://engagedfamilygaming.com/the-esrb-rating-system-what-parents-need-to-know/
- Villains mischievous, not scary: round, colourful, clumsy, funny voices, no menacing music, no blood. Defeat by bubbling, tickling or befriending, never injury. Why: ages 3-5 fear how things look and cannot separate fantasy from reality; avoid helpless heroes or missing caregivers. https://mediasmarts.ca/teacher-resources/dealing-fear-and-media
- No ads, no IAP, no third-party analytics. Apple's Kids Category bans third-party analytics/ads except narrow cases and puts links-out and purchases behind a parental gate. https://developer.apple.com/app-store/review/guidelines/
- Google Play Families allows only certified ad SDKs and no persistent identifiers; simply avoid ads entirely. https://support.google.com/googleplay/android-developer/answer/9893335
- No data collection: no accounts, chat or analytics; progress in localStorage; self-host fonts and libraries so there are no third-party calls at runtime [inf]. Why: the 2025 COPPA amendments (compliance April 22, 2026) require separate consent for non-integral third-party disclosure, a security program and a retention policy. Portugal sets digital consent at 13, so under-13s need guardian consent. https://www.federalregister.gov/documents/2025/04/22/2025-05904/childrens-online-privacy-protection-rule and https://www.bas.pt/en/communication/news/the-consent-of-minors-and-the-gdpr/
- Parental gate on any external link (book shop, website): an adult-level task needing maths plus dexterity, voiced for pre-readers, with lockout. https://developer.apple.com/kids/
- No dark patterns (fake timers, FOMO, disguised purchases). Why: the FTC's Epic settlement was $275M for children's privacy plus $245M refunds for dark-pattern billing. https://www.fenwick.com/insights/publications/ftcs-aggressive-enforcement-of-childrens-privacy-and-dark-patterns-a-cautionary-tale-and-simple-steps-companies-can-take-to-reduce-risk

8. TESTING WITH KIDS
- Observe behaviour, not answers: body language, laughter, comments, how easily they clear challenges. Note when attention drifts away without frustration, which means engagement ended. https://joanganzcooneycenter.org/2013/10/01/first-contact-playtesting-with-preschoolers/
- Think-aloud works poorly with children; use talk-aloud and ask them to be the experts teaching you. https://dl.acm.org/doi/10.1145/1017833.1017848 and https://www.nngroup.com/articles/usability-testing-minors/
- Brief parents to keep hands off, because they often take over and the child stops learning. Recruit extras (about 1 in 9 no-show) and do not mix all ages. https://richard-marmura.squarespace.com/rich-marmura/2018/10/16/playtesting-with-children-getting-useful-feedback-to-improve-your-game
- Watch for [inf]: first 60 s without help; thumb placement and palm touches on tablets; spots with 3+ retries; whether kids tap text to hear it; reaction to each villain (laugh or recoil); who holds the controls in co-op and whether the helper stays engaged; sound muted.
- Pass gate [inf]: 8 of 10 kids clear chapter 1 unaided, nobody is stuck over 30 s without a hint, and zero recoil at villains.

TOP 12 FOR THIS GAME (ordered)
1. Never fail: no game over, bubble rescue, instant respawn, regenerating health.
2. Voice-first, icon-first: all instructions and story spoken in PT-PT with read-along highlight and an EN toggle.
3. One stick plus at most 2 buttons, auto-aim, no holds or mashing.
4. Touch targets 76px minimum (96px for actions), floating joystick, thumb-safe layout.
5. Auto-camera that needs no manual input.
6. Drop-in co-op: invincible helper role, shared goals, partner never left behind.
7. Zero ads, IAP, accounts, analytics or third-party calls; parental gate on any link.
8. Mischievous villains, PEGI 3 content, caregivers never in peril.
9. 6-10 minute chapters with skippable page-turn cutscenes, autosave and book-page rewards.
10. Photosensitivity and motion safety: no full-screen flashes, shake off or minimal, Flashing toggle.
11. Positive-only feedback plus an idle hint ladder (4 s, 8 s).
12. Playtest with real 4-8 year olds and parents before each chapter locks.