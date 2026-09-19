// Словарь критика: термины, которые автор вставляет в рецензию ссылкой
// `[слово](term:id)`. Читатель нажимает на слово с пунктиром и видит
// определение на своём языке, поэтому в тексте хранится только id.
// Новый термин — запись на всех семи языках (стережёт review_glossary_test).

import '../l10n/locale_controller.dart';

enum TermGroup { story, camera, sound, genre }

class CriticTerm {
  final String id;
  final TermGroup group;
  final Map<String, String> name;
  final Map<String, String> def;

  const CriticTerm(this.id, this.group, this.name, this.def);

  static String _pick(Map<String, String> m) =>
      m[LocaleController.instance.code] ?? m['en'] ?? m.values.first;

  String get localName => _pick(name);
  String get localDef => _pick(def);
}

CriticTerm? criticTerm(String? id) {
  for (final t in kCriticTerms) {
    if (t.id == id) return t;
  }
  return null;
}

const List<CriticTerm> kCriticTerms = [
  // ------------------------------- Сюжет -------------------------------
  CriticTerm('twist', TermGroup.story, {
    'ru': 'Твист',
    'en': 'Plot twist',
    'de': 'Plot-Twist',
    'fr': 'Rebondissement',
    'es': 'Giro argumental',
    'it': 'Colpo di scena',
    'pt': 'Reviravolta',
  }, {
    'ru': 'Неожиданный поворот, после которого всё увиденное читается иначе.',
    'en': 'An unexpected turn that makes you reread everything you have seen.',
    'de': 'Eine unerwartete Wendung, nach der man alles Gesehene neu deutet.',
    'fr': 'Un tournant inattendu qui oblige à relire tout ce qu’on a vu.',
    'es': 'Un giro inesperado que obliga a releer todo lo visto.',
    'it': 'Una svolta inattesa che cambia il senso di tutto ciò che si è visto.',
    'pt': 'Uma virada inesperada que muda o sentido de tudo o que se viu.',
  }),
  CriticTerm('unreliable_narrator', TermGroup.story, {
    'ru': 'Ненадёжный рассказчик',
    'en': 'Unreliable narrator',
    'de': 'Unzuverlässiger Erzähler',
    'fr': 'Narrateur non fiable',
    'es': 'Narrador no fiable',
    'it': 'Narratore inattendibile',
    'pt': 'Narrador não confiável',
  }, {
    'ru': 'Герой, глазами которого мы смотрим, обманывает зрителя или самого себя.',
    'en': 'The character whose eyes we see through deceives the viewer or himself.',
    'de': 'Die Figur, durch deren Augen wir sehen, täuscht das Publikum oder sich selbst.',
    'fr': 'Le personnage dont on partage le regard trompe le spectateur ou se trompe lui-même.',
    'es': 'El personaje a través de cuyos ojos miramos engaña al público o a sí mismo.',
    'it': 'Il personaggio attraverso cui guardiamo inganna lo spettatore o se stesso.',
    'pt': 'O personagem por cujos olhos vemos engana o público ou a si mesmo.',
  }),
  CriticTerm('red_herring', TermGroup.story, {
    'ru': 'Ложный след',
    'en': 'Red herring',
    'de': 'Falsche Fährte',
    'fr': 'Fausse piste',
    'es': 'Pista falsa',
    'it': 'Falsa pista',
    'pt': 'Pista falsa',
  }, {
    'ru': 'Улика, которая уводит зрителя от разгадки.',
    'en': 'A clue planted to lead the viewer away from the solution.',
    'de': 'Ein Hinweis, der das Publikum von der Lösung weglockt.',
    'fr': 'Un indice qui éloigne le spectateur de la solution.',
    'es': 'Una pista que aleja al público de la solución.',
    'it': 'Un indizio che allontana lo spettatore dalla soluzione.',
    'pt': 'Uma pista que afasta o público da solução.',
  }),
  CriticTerm('macguffin', TermGroup.story, {
    'ru': 'Макгаффин',
    'en': 'MacGuffin',
    'de': 'MacGuffin',
    'fr': 'MacGuffin',
    'es': 'MacGuffin',
    'it': 'MacGuffin',
    'pt': 'MacGuffin',
  }, {
    'ru': 'Предмет, за которым все гоняются. Двигает сюжет, но сам по себе ничего не значит.',
    'en': 'The object everyone chases. It drives the plot but means nothing in itself.',
    'de': 'Das Objekt, hinter dem alle her sind. Es treibt die Handlung an, bedeutet aber selbst nichts.',
    'fr': 'L’objet que tout le monde poursuit. Il fait avancer l’intrigue mais ne compte pas en soi.',
    'es': 'El objeto que todos persiguen. Mueve la trama, pero por sí mismo no significa nada.',
    'it': 'L’oggetto che tutti inseguono. Muove la trama ma di per sé non conta nulla.',
    'pt': 'O objeto que todos perseguem. Move a trama, mas em si não significa nada.',
  }),
  CriticTerm('deus_ex_machina', TermGroup.story, {
    'ru': 'Бог из машины',
    'en': 'Deus ex machina',
    'de': 'Deus ex machina',
    'fr': 'Deus ex machina',
    'es': 'Deus ex machina',
    'it': 'Deus ex machina',
    'pt': 'Deus ex machina',
  }, {
    'ru': 'Проблему решает случай или внезапная сила со стороны, а не сами герои.',
    'en': 'A problem solved by luck or a sudden outside force instead of the characters.',
    'de': 'Ein Problem löst der Zufall oder eine plötzliche äußere Kraft, nicht die Figuren.',
    'fr': 'Le problème se règle par hasard ou par une force extérieure, pas grâce aux héros.',
    'es': 'El problema lo resuelve el azar o una fuerza externa, no los personajes.',
    'it': 'Il problema si risolve per caso o per una forza esterna, non grazie ai personaggi.',
    'pt': 'O problema é resolvido pelo acaso ou por uma força externa, não pelos personagens.',
  }),
  CriticTerm('character_arc', TermGroup.story, {
    'ru': 'Арка героя',
    'en': 'Character arc',
    'de': 'Figurenbogen',
    'fr': 'Arc du personnage',
    'es': 'Arco del personaje',
    'it': 'Arco del personaggio',
    'pt': 'Arco do personagem',
  }, {
    'ru': 'Путь, которым герой меняется от начала истории к финалу.',
    'en': 'How a character changes from the start of the story to the end.',
    'de': 'Wie sich eine Figur vom Anfang bis zum Ende der Geschichte verändert.',
    'fr': 'La façon dont un personnage change du début à la fin de l’histoire.',
    'es': 'Cómo cambia un personaje desde el inicio hasta el final de la historia.',
    'it': 'Come un personaggio cambia dall’inizio alla fine della storia.',
    'pt': 'Como um personagem muda do começo ao fim da história.',
  }),
  CriticTerm('chekhovs_gun', TermGroup.story, {
    'ru': 'Чеховское ружьё',
    'en': 'Chekhov’s gun',
    'de': 'Tschechows Gewehr',
    'fr': 'Fusil de Tchekhov',
    'es': 'Arma de Chéjov',
    'it': 'Pistola di Čechov',
    'pt': 'Arma de Tchekhov',
  }, {
    'ru': 'Деталь из начала, которая обязательно сработает ближе к финалу.',
    'en': 'A detail shown early that is sure to pay off near the end.',
    'de': 'Ein früh gezeigtes Detail, das gegen Ende garantiert zum Tragen kommt.',
    'fr': 'Un détail montré tôt qui servira forcément vers la fin.',
    'es': 'Un detalle mostrado al principio que sin falta se usará hacia el final.',
    'it': 'Un dettaglio mostrato all’inizio che tornerà di sicuro verso il finale.',
    'pt': 'Um detalhe mostrado no início que com certeza será usado perto do fim.',
  }),
  CriticTerm('open_ending', TermGroup.story, {
    'ru': 'Открытый финал',
    'en': 'Open ending',
    'de': 'Offenes Ende',
    'fr': 'Fin ouverte',
    'es': 'Final abierto',
    'it': 'Finale aperto',
    'pt': 'Final aberto',
  }, {
    'ru': 'Концовка, которая оставляет главный вопрос зрителю.',
    'en': 'An ending that leaves the main question to the viewer.',
    'de': 'Ein Schluss, der die zentrale Frage dem Publikum überlässt.',
    'fr': 'Une fin qui laisse la question principale au spectateur.',
    'es': 'Un final que deja la pregunta principal al espectador.',
    'it': 'Un finale che lascia la domanda principale allo spettatore.',
    'pt': 'Um final que deixa a pergunta principal para o espectador.',
  }),
  // --------------------------- Камера и монтаж ---------------------------
  CriticTerm('mise_en_scene', TermGroup.camera, {
    'ru': 'Мизансцена',
    'en': 'Mise-en-scène',
    'de': 'Mise en Scène',
    'fr': 'Mise en scène',
    'es': 'Puesta en escena',
    'it': 'Messa in scena',
    'pt': 'Mise-en-scène',
  }, {
    'ru': 'Как в кадре расставлены актёры, свет и предметы.',
    'en': 'How actors, light and objects are arranged in the frame.',
    'de': 'Wie Schauspieler, Licht und Gegenstände im Bild angeordnet sind.',
    'fr': 'La façon dont acteurs, lumière et objets sont disposés dans le cadre.',
    'es': 'Cómo se colocan en el encuadre los actores, la luz y los objetos.',
    'it': 'Come attori, luci e oggetti sono disposti nell’inquadratura.',
    'pt': 'Como atores, luz e objetos são dispostos no quadro.',
  }),
  CriticTerm('long_take', TermGroup.camera, {
    'ru': 'Длинный план',
    'en': 'Long take',
    'de': 'Plansequenz',
    'fr': 'Plan-séquence',
    'es': 'Plano secuencia',
    'it': 'Piano sequenza',
    'pt': 'Plano-sequência',
  }, {
    'ru': 'Сцена снята одним кадром, без склеек.',
    'en': 'A scene filmed in one continuous shot, without cuts.',
    'de': 'Eine Szene in einer einzigen Einstellung, ohne Schnitt.',
    'fr': 'Une scène filmée d’un seul tenant, sans coupe.',
    'es': 'Una escena rodada en una sola toma, sin cortes.',
    'it': 'Una scena girata in un’unica ripresa, senza tagli.',
    'pt': 'Uma cena filmada numa só tomada, sem cortes.',
  }),
  CriticTerm('montage', TermGroup.camera, {
    'ru': 'Монтажная нарезка',
    'en': 'Montage',
    'de': 'Montagesequenz',
    'fr': 'Séquence de montage',
    'es': 'Montaje',
    'it': 'Sequenza di montaggio',
    'pt': 'Montagem',
  }, {
    'ru': 'Цепочка коротких сцен, которая сжимает дни или годы в минуту экрана.',
    'en': 'A chain of short scenes that squeezes days or years into a minute.',
    'de': 'Eine Kette kurzer Szenen, die Tage oder Jahre auf eine Minute verdichtet.',
    'fr': 'Une suite de courtes scènes qui condense des jours ou des années en une minute.',
    'es': 'Una cadena de escenas cortas que condensa días o años en un minuto.',
    'it': 'Una serie di brevi scene che condensa giorni o anni in un minuto.',
    'pt': 'Uma sequência de cenas curtas que condensa dias ou anos em um minuto.',
  }),
  CriticTerm('color_grading', TermGroup.camera, {
    'ru': 'Цветокоррекция',
    'en': 'Color grading',
    'de': 'Farbkorrektur',
    'fr': 'Étalonnage',
    'es': 'Etalonaje',
    'it': 'Color correction',
    'pt': 'Correção de cor',
  }, {
    'ru': 'Цветовое решение фильма, которое задаёт настроение.',
    'en': 'The color palette of a film, used to set its mood.',
    'de': 'Die Farbgebung eines Films, die seine Stimmung bestimmt.',
    'fr': 'Le traitement des couleurs qui donne au film son ambiance.',
    'es': 'El tratamiento del color que marca el tono de la película.',
    'it': 'Il trattamento del colore che dà al film la sua atmosfera.',
    'pt': 'O tratamento de cor que define o clima do filme.',
  }),
  CriticTerm('dutch_angle', TermGroup.camera, {
    'ru': 'Голландский угол',
    'en': 'Dutch angle',
    'de': 'Gekippte Kamera',
    'fr': 'Plan cassé',
    'es': 'Plano holandés',
    'it': 'Inquadratura obliqua',
    'pt': 'Ângulo holandês',
  }, {
    'ru': 'Камера завалена набок, и мир в кадре выглядит тревожным.',
    'en': 'The camera is tilted, so the world in the frame feels uneasy.',
    'de': 'Die Kamera ist schräg gestellt, die Welt im Bild wirkt beunruhigend.',
    'fr': 'La caméra est inclinée et le monde à l’écran paraît inquiétant.',
    'es': 'La cámara está inclinada y el mundo del encuadre resulta inquietante.',
    'it': 'La camera è inclinata e il mondo inquadrato appare inquietante.',
    'pt': 'A câmera fica inclinada e o mundo no quadro parece inquietante.',
  }),
  // -------------------------------- Звук --------------------------------
  CriticTerm('diegetic_sound', TermGroup.sound, {
    'ru': 'Внутрикадровый звук',
    'en': 'Diegetic sound',
    'de': 'Diegetischer Ton',
    'fr': 'Son diégétique',
    'es': 'Sonido diegético',
    'it': 'Suono diegetico',
    'pt': 'Som diegético',
  }, {
    'ru': 'Звук, который слышат и сами герои: радио в машине, песня в баре.',
    'en': 'Sound the characters hear too: a car radio, a song in a bar.',
    'de': 'Ton, den auch die Figuren hören: Autoradio, ein Lied in der Bar.',
    'fr': 'Un son que les personnages entendent aussi : autoradio, chanson dans un bar.',
    'es': 'Sonido que también oyen los personajes: la radio del coche, una canción en un bar.',
    'it': 'Suono che sentono anche i personaggi: l’autoradio, una canzone al bar.',
    'pt': 'Som que os personagens também ouvem: o rádio do carro, uma música no bar.',
  }),
  CriticTerm('original_score', TermGroup.sound, {
    'ru': 'Оригинальная музыка',
    'en': 'Original score',
    'de': 'Filmmusik',
    'fr': 'Musique originale',
    'es': 'Banda sonora original',
    'it': 'Colonna sonora originale',
    'pt': 'Trilha sonora original',
  }, {
    'ru': 'Музыка, написанная для фильма. Её слышит только зритель.',
    'en': 'Music written for the film. Only the audience hears it.',
    'de': 'Für den Film komponierte Musik. Nur das Publikum hört sie.',
    'fr': 'Musique composée pour le film. Seul le spectateur l’entend.',
    'es': 'Música compuesta para la película. Solo la oye el público.',
    'it': 'Musica scritta per il film. La sente solo lo spettatore.',
    'pt': 'Música composta para o filme. Só o público a ouve.',
  }),
  CriticTerm('leitmotif', TermGroup.sound, {
    'ru': 'Лейтмотив',
    'en': 'Leitmotif',
    'de': 'Leitmotiv',
    'fr': 'Leitmotiv',
    'es': 'Leitmotiv',
    'it': 'Leitmotiv',
    'pt': 'Leitmotiv',
  }, {
    'ru': 'Мелодия, которая возвращается вместе с героем или темой.',
    'en': 'A tune that returns along with a character or theme.',
    'de': 'Eine Melodie, die mit einer Figur oder einem Thema wiederkehrt.',
    'fr': 'Un air qui revient avec un personnage ou un thème.',
    'es': 'Una melodía que vuelve junto a un personaje o un tema.',
    'it': 'Una melodia che ritorna insieme a un personaggio o a un tema.',
    'pt': 'Uma melodia que volta junto com um personagem ou tema.',
  }),
  // ----------------------------- Жанр и тон -----------------------------
  CriticTerm('noir', TermGroup.genre, {
    'ru': 'Нуар',
    'en': 'Noir',
    'de': 'Film noir',
    'fr': 'Film noir',
    'es': 'Cine negro',
    'it': 'Noir',
    'pt': 'Noir',
  }, {
    'ru': 'Мрачный детектив: тени, дождь, усталый герой с грехом в прошлом.',
    'en': 'A dark crime story: shadows, rain, a weary hero with a past.',
    'de': 'Düsterer Krimi: Schatten, Regen, ein müder Held mit Vergangenheit.',
    'fr': 'Polar sombre : ombres, pluie, héros las au passé trouble.',
    'es': 'Policiaco sombrío: sombras, lluvia, un héroe cansado con un pasado turbio.',
    'it': 'Poliziesco cupo: ombre, pioggia, un eroe stanco con un passato oscuro.',
    'pt': 'Policial sombrio: sombras, chuva, um herói cansado com passado obscuro.',
  }),
  CriticTerm('suspense', TermGroup.genre, {
    'ru': 'Саспенс',
    'en': 'Suspense',
    'de': 'Suspense',
    'fr': 'Suspense',
    'es': 'Suspense',
    'it': 'Suspense',
    'pt': 'Suspense',
  }, {
    'ru': 'Зритель знает об опасности раньше героя и ждёт, когда она сработает.',
    'en': 'The audience knows about the danger before the hero and waits for it.',
    'de': 'Das Publikum kennt die Gefahr vor der Figur und wartet, bis sie eintritt.',
    'fr': 'Le spectateur connaît le danger avant le héros et attend qu’il frappe.',
    'es': 'El público conoce el peligro antes que el héroe y espera a que estalle.',
    'it': 'Lo spettatore conosce il pericolo prima dell’eroe e aspetta che scatti.',
    'pt': 'O público sabe do perigo antes do herói e espera que ele aconteça.',
  }),
  CriticTerm('slow_burn', TermGroup.genre, {
    'ru': 'Слоубёрн',
    'en': 'Slow burn',
    'de': 'Slow Burn',
    'fr': 'Tension lente',
    'es': 'Cocción lenta',
    'it': 'Slow burn',
    'pt': 'Slow burn',
  }, {
    'ru': 'История разгоняется медленно и копит напряжение к финалу.',
    'en': 'A story that starts slowly and builds tension toward the end.',
    'de': 'Eine Geschichte, die langsam anläuft und Spannung zum Ende hin aufbaut.',
    'fr': 'Une histoire qui démarre lentement et accumule la tension jusqu’à la fin.',
    'es': 'Una historia que arranca despacio y acumula tensión hasta el final.',
    'it': 'Una storia che parte piano e accumula tensione fino al finale.',
    'pt': 'Uma história que começa devagar e acumula tensão até o fim.',
  }),
  CriticTerm('fourth_wall', TermGroup.genre, {
    'ru': 'Четвёртая стена',
    'en': 'Fourth wall',
    'de': 'Vierte Wand',
    'fr': 'Quatrième mur',
    'es': 'Cuarta pared',
    'it': 'Quarta parete',
    'pt': 'Quarta parede',
  }, {
    'ru': 'Невидимая граница между героями и зрителем. Сломать её — заговорить с залом.',
    'en': 'The invisible line between characters and audience. Breaking it means talking to us.',
    'de': 'Die unsichtbare Grenze zwischen Figuren und Publikum. Sie zu brechen heißt, uns anzusprechen.',
    'fr': 'La frontière invisible entre personnages et public. La briser, c’est s’adresser à nous.',
    'es': 'La frontera invisible entre personajes y público. Romperla es hablarnos a nosotros.',
    'it': 'Il confine invisibile tra personaggi e pubblico. Romperlo è parlare a noi.',
    'pt': 'A fronteira invisível entre personagens e público. Quebrá-la é falar conosco.',
  }),
  CriticTerm('filler', TermGroup.genre, {
    'ru': 'Филлер',
    'en': 'Filler',
    'de': 'Filler',
    'fr': 'Épisode de remplissage',
    'es': 'Relleno',
    'it': 'Filler',
    'pt': 'Filler',
  }, {
    'ru': 'Серия, которая почти не двигает общий сюжет.',
    'en': 'An episode that barely moves the main story forward.',
    'de': 'Eine Folge, die die Haupthandlung kaum voranbringt.',
    'fr': 'Un épisode qui fait à peine avancer l’intrigue principale.',
    'es': 'Un episodio que apenas hace avanzar la trama principal.',
    'it': 'Un episodio che fa avanzare appena la trama principale.',
    'pt': 'Um episódio que quase não faz avançar a trama principal.',
  }),
];
