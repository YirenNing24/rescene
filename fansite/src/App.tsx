import { createEffect, createMemo, createSignal, onSettled } from "solid-js";
import {
  ArrowUpRight,
  ArrowRight,
  Search,
  X,
  Menu,
  Heart,
  Play,
  Sparkles,
  Music2,
  Layers,
  Check,
  RotateCcw,
  ExternalLink,
} from "./Icons";
import "./styles.css";

const members = [
  {
    name: "WONI",
    korean: "원이",
    image: "woni",
    line: "The beginning of every scene.",
    detail:
      "Meet Woni, the leader of RESCENE. Start with her PULSE concept portrait, then explore her performances with all five members.",
  },
  {
    name: "LIV",
    korean: "리브",
    image: "liv",
    line: "A presence all her own.",
    detail:
      "Meet Liv, one of the five voices of RESCENE. Discover her PULSE concept portrait and find your favorite moments in the group's music videos.",
  },
  {
    name: "MINAMI",
    korean: "미나미",
    image: "minami",
    line: "A little spark. A lasting impression.",
    detail:
      "Meet Minami, RESCENE's Japanese member. Explore her PULSE concept portrait and discover the voice and energy she brings to the group.",
  },
  {
    name: "MAY",
    korean: "메이",
    image: "may",
    line: "Your next favorite moment.",
    detail:
      "Meet May, one of the five members of RESCENE. Explore her PULSE concept portrait and watch her bring each new musical scene to life.",
  },
  {
    name: "ZENA",
    korean: "제나",
    image: "zena",
    line: "A scene you won't forget.",
    detail:
      "Meet Zena, the youngest member of RESCENE. Explore her PULSE concept portrait and get to know her through the group's performances.",
  },
];
const albums = [
  {
    name: "PULSE",
    type: "MINI ALBUM",
    image: "pulse",
    songs: "Runaway · Dragon · Finest Thing",
    category: "Mini albums",
  },
  {
    name: "lip bomb",
    type: "MINI ALBUM",
    image: "lip-bomb",
    songs: "Bloom · Heart Drop · lip bomb",
    category: "Mini albums",
  },
  {
    name: "Glow Up",
    type: "MINI ALBUM",
    image: "glow-up",
    songs: "Glow Up · Cotton Candy · CRASH",
    category: "Mini albums",
  },
  {
    name: "Dearest",
    type: "SINGLE ALBUM",
    image: "dearest",
    songs: "Deja Vu · Mood",
    category: "Singles",
  },
  {
    name: "SCENEDROME",
    type: "MINI ALBUM",
    image: "scenedrome",
    songs: "LOVE ATTACK · Pinball",
    category: "Mini albums",
  },
];
const questions = [
  {
    q: "How many members make up RESCENE?",
    options: ["Four", "Five", "Six"],
    answer: 1,
  },
  {
    q: "What's the name of RESCENE's fandom?",
    options: ["REMINE", "BLINK", "MY"],
    answer: 0,
  },
  {
    q: "Which song is on SCENEDROME?",
    options: ["Glow Up", "Deja Vu", "LOVE ATTACK"],
    answer: 2,
  },
  {
    q: "Who is RESCENE's leader?",
    options: ["Minami", "Woni", "Zena"],
    answer: 1,
  },
];
type Modal =
  | { kind: "member"; index: number }
  | { kind: "quiz" }
  | { kind: "collection" }
  | { kind: "guide" }
  | { kind: "about" }
  | null;
const official = "https://www.youtube.com/@RESCENE_official";
const musicLink = (name: string) =>
  `https://open.spotify.com/search/${encodeURIComponent("RESCENE " + name)}`;
export default function App() {
  const [menu, setMenu] = createSignal(false),
    [search, setSearch] = createSignal(false),
    [query, setQuery] = createSignal("");
  const [modal, setModal] = createSignal<Modal>(null),
    [filter, setFilter] = createSignal("All releases"),
    [saved, setSaved] = createSignal<string[]>([]),
    [vote, setVote] = createSignal("");
  const [step, setStep] = createSignal(0),
    [answers, setAnswers] = createSignal<number[]>([]);
  let dialogRef: HTMLDialogElement | undefined;
  let triggerRef: HTMLElement | null = null;
  const memberIndex = () => {
    const current = modal();
    return current?.kind === "member" ? current.index : 0;
  };
  onSettled(() => {
    try {
      const cards: unknown = JSON.parse(
        localStorage.getItem("remine-cards") || "[]",
      );
      if (Array.isArray(cards))
        setSaved(
          cards.filter(
            (v): v is string =>
              typeof v === "string" && members.some((m) => m.image === v),
          ),
        );
      const pick = localStorage.getItem("remine-pick") || "";
      if (["LOVE ATTACK", "Glow Up", "Runaway"].includes(pick)) setVote(pick);
    } catch {}
    const key = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setSearch((v) => !v);
        setModal(null);
      }
    };
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  });
  createEffect(
    () => ({ active: !!(modal() || search()), search: search() }),
    ({ active, search }) => {
      const d = dialogRef;
      if (!d) return;
      if (active) {
        if (!d.open) {
          triggerRef = document.activeElement as HTMLElement;
          d.showModal();
        }
        if (search) d.querySelector<HTMLInputElement>("input")?.focus();
      } else {
        if (d.open) d.close();
        triggerRef?.focus();
      }
    },
  );
  function close() {
    setModal(null);
    setSearch(false);
  }
  function collect(name: string) {
    const current = saved();
    const next = current.includes(name)
      ? current.filter((n) => n !== name)
      : [...current, name];
    setSaved(next);
    try {
      localStorage.setItem("remine-cards", JSON.stringify(next));
    } catch {}
  }
  function chooseVote(song: string) {
    setVote(song);
    try {
      localStorage.setItem("remine-pick", song);
    } catch {}
  }
  function openQuiz() {
    setStep(0);
    setAnswers([]);
    setModal({ kind: "quiz" });
  }
  const searchItems = createMemo(() =>
    [
      ...members.map((m, i) => ({
        title: m.name,
        detail: "Member profile",
        action: () => {
          setSearch(false);
          setModal({ kind: "member", index: i });
        },
      })),
      ...albums.map((a) => ({
        title: a.name,
        detail: "Explore the music",
        action: () => {
          close();
          setFilter("All releases");
          document
            .getElementById("music")
            ?.scrollIntoView({
              behavior: window.matchMedia("(prefers-reduced-motion: reduce)")
                .matches
                ? "instant"
                : "smooth",
            });
        },
      })),
      {
        title: "Fan quiz",
        detail: "Test your knowledge",
        action: () => {
          setSearch(false);
          openQuiz();
        },
      },
      {
        title: "My photocards",
        detail: "Your PULSE portraits",
        action: () => {
          setSearch(false);
          setModal({ kind: "collection" });
        },
      },
    ].filter((i) =>
      (i.title + " " + i.detail).toLowerCase().includes(query().toLowerCase()),
    ),
  );
  return (
    <>
      <a class="skip-link" href="#main">
        Skip to content
      </a>
      <header class="header">
        <div class="header-inner">
          <a class="brand" href="#" aria-label="RESCENE home">
            RE<span>SCENE</span>
            <i>FAN COLLECTIVE</i>
          </a>
          <nav
            class={menu() ? "nav is-open" : "nav"}
            aria-label="Main navigation"
          >
            {[
              ["Home", "#"],
              ["Discover", "#discover"],
              ["Members", "#members"],
              ["Music", "#music"],
              ["For REMINE", "#community"],
              ["RESCENE Rhythm", "https://rhythm.remineph.online"],
            ].map(([label, href], i) => (
              <a
                href={href}
                class={i === 0 ? "active" : i === 5 ? "rhythm-nav" : ""}
                onClick={() => setMenu(false)}
              >
                {label}
                {i === 4 && <span class="nav-dot" />}
              </a>
            ))}
          </nav>
          <div class="header-actions">
            <button
              class="search-button"
              aria-label="Search site"
              onClick={() => {
                setQuery("");
                setSearch(true);
              }}
            >
              <Search size={17} />
              <kbd>⌘ K</kbd>
            </button>
            <span class="header-divider" />
            <button
              class="collection-button"
              onClick={() => setModal({ kind: "collection" })}
            >
              <Heart size={16} />
              <span>My collection</span>
              {saved().length > 0 && <b>{saved().length}</b>}
            </button>
            <button
              class="mobile-toggle icon-button"
              aria-label={menu() ? "Close navigation" : "Open navigation"}
              aria-expanded={menu() ? "true" : "false"}
              onClick={() => setMenu(!menu())}
            >
              {menu() ? <X /> : <Menu />}
            </button>
          </div>
        </div>
      </header>
      <main id="main">
        <section class="hero" aria-labelledby="hero-title">
          <div class="hero-photo">
            <img
              src="/images/group.webp"
              alt="All five RESCENE members in white PULSE concept outfits"
              fetchpriority="high"
            />
            <span class="photo-label">PULSE — THE 4TH MINI ALBUM</span>
          </div>
          <div class="hero-shade" />
          <div class="hero-content wrap">
            <p class="eyebrow">
              <span class="star">✦</span> AN INDEPENDENT RESCENE FAN SPACE
            </p>
            <h1 id="hero-title">
              Five voices.
              <br />
              Endless <em>scenes.</em>
            </h1>
            <p class="hero-description">
              A little closer to RESCENE.
              <br /> The music, the moments, and the people
              <br class="desktop-break" /> who make it all mean more.
            </p>
            <div class="hero-buttons">
              <a class="button primary" href="#discover">
                Find your scene <ArrowUpRight size={17} />
              </a>
              <a class="button glass rhythm-entry" href="https://rhythm.remineph.online">
                <Music2 size={16} /> RESCENE Rhythm <ArrowUpRight size={16} />
              </a>
              <a
                class="button glass"
                href={official}
                target="_blank"
                rel="noreferrer"
              >
                <Play size={14} fill="currentColor" /> Watch RESCENE
              </a>
            </div>
            <div class="hero-credit">
              <span class="little-line" />
              Made by fans. For REMINE. <Heart size={12} />
            </div>
          </div>
          <div class="hero-bottom wrap">
            <span>
              WONI <b>·</b> LIV <b>·</b> MINAMI <b>·</b> MAY <b>·</b> ZENA
            </span>
            <a href="#discover">
              SCROLL TO DISCOVER <span>↓</span>
            </a>
          </div>
          <span class="hero-side">A SCENE THAT STAYS WITH YOU.</span>
        </section>
        <div class="scene-strip">
          <div class="wrap">
            <span>
              <i />
              WELCOME TO YOUR NEXT OBSESSION
            </span>
            <p>One group. Five reasons to stay.</p>
            <span class="strip-sign">
              RESCENE <span>×</span> REMINE <Sparkles size={15} />
            </span>
          </div>
        </div>
        <section id="discover" class="section wrap discovery">
          <div class="section-heading">
            <div>
              <p class="eyebrow">MAKE YOURSELF AT HOME</p>
              <h2>
                Your RESCENE starts here<span>.</span>
              </h2>
            </div>
            <p>
              New here or here since day one,
              <br />
              there’s a scene for you.
            </p>
          </div>
          <div class="destination-grid">
            <a class="destination" href="#members">
              <span class="destination-top">
                <span>01 / DISCOVER</span>
                <Sparkles size={23} />
              </span>
              <h3>Meet the five.</h3>
              <p>The faces behind your favorite songs.</p>
              <span class="destination-link">
                Get to know RESCENE <ArrowUpRight size={19} />
              </span>
            </a>
            <a class="destination" href="#music">
              <span class="destination-top">
                <span>02 / LISTEN</span>
                <Music2 size={23} />
              </span>
              <h3>Find your sound.</h3>
              <p>Every era. Every track. On repeat.</p>
              <span class="destination-link">
                Explore the music <ArrowUpRight size={19} />
              </span>
            </a>
            <button class="destination" onClick={openQuiz}>
              <span class="destination-top">
                <span>03 / PLAY</span>
                <span class="quiz-symbol">?</span>
              </span>
              <h3>How REMINE are you?</h3>
              <p>A little challenge for your inner fan.</p>
              <span class="destination-link">
                Take the fan quiz <ArrowUpRight size={19} />
              </span>
            </button>
            <button
              class="destination"
              onClick={() => setModal({ kind: "collection" })}
            >
              <span class="destination-top">
                <span>04 / COLLECT</span>
                <Layers size={23} />
              </span>
              <h3>Keep the moment.</h3>
              <p>Your favorite faces. Your own collection.</p>
              <span class="destination-link">
                Explore photocards <ArrowUpRight size={19} />
              </span>
            </button>
          </div>
        </section>
        <section id="members" class="section wrap members-section">
          <div class="section-heading">
            <div>
              <p class="eyebrow">FIVE INDIVIDUALS. ONE RESCENE.</p>
              <h2>
                A scene for every bias<span>.</span>
              </h2>
            </div>
            <span class="section-note">
              GET TO KNOW THE MEMBERS <span>↙</span>
            </span>
          </div>
          <div class="member-grid">
            {members.map((m, i) => (
              <button
                class="member"
                onClick={() => setModal({ kind: "member", index: i })}
              >
                <div class="member-photo">
                  <img
                    src={`/images/${m.image}.webp`}
                    alt={`${m.name} — PULSE concept portrait`}
                    loading="lazy"
                  />
                  <span class="member-number">0{i + 1}</span>
                  <span class="profile-pill">
                    Explore profile <ArrowUpRight size={14} />
                  </span>
                </div>
                <div class="member-caption">
                  <h3>
                    {m.name}
                    <span>{m.korean}</span>
                  </h3>
                  <ArrowUpRight size={19} />
                </div>
              </button>
            ))}
          </div>
          <div class="members-foot">
            <span>Different colors. The same beautiful scene.</span>
            <span>
              WONI · LIV · MINAMI · MAY · ZENA <Heart size={12} />
            </span>
          </div>
        </section>
        <section class="era-section">
          <div class="wrap era-grid">
            <div class="era-art">
              <img
                src="/images/pulse.webp"
                alt="PULSE album artwork"
                loading="lazy"
              />
              <span class="era-stamp">
                ON OUR
                <br />
                <b>RADAR</b>
                <Sparkles size={19} />
              </span>
            </div>
            <div class="era-copy">
              <p class="eyebrow">
                <span class="lavender-dot" /> THE PULSE ERA
              </p>
              <h2>
                Feel the <em>PULSE.</em>
              </h2>
              <p>
                A new scene to get lost in. Step into the world of RESCENE’s
                fourth mini album, from its ethereal concept portraits to the
                songs you’ll keep coming back to.
              </p>
              <div class="track-tags">
                <span>Runaway</span>
                <span>Dragon</span>
                <span>Finest Thing</span>
              </div>
              <a
                class="button primary"
                href={musicLink("PULSE")}
                target="_blank"
                rel="noreferrer"
              >
                <Music2 size={17} /> Explore the album{" "}
                <ArrowUpRight size={17} />
              </a>
              <span class="era-caption">HEADPHONES ON. WORLD OFF.</span>
            </div>
          </div>
        </section>
        <section id="music" class="section wrap">
          <div class="section-heading">
            <div>
              <p class="eyebrow">THE SOUNDTRACK TO YOUR SCENE</p>
              <h2>
                Some songs just stay<span>.</span>
              </h2>
            </div>
            <a
              href={musicLink("")}
              class="text-link"
              target="_blank"
              rel="noreferrer"
            >
              Find RESCENE on Spotify <ArrowUpRight size={16} />
            </a>
          </div>
          <div class="music-toolbar">
            <div class="filter-tabs" aria-label="Filter releases">
              {["All releases", "Mini albums", "Singles"].map((tab) => (
                <button
                  aria-pressed={filter() === tab ? "true" : "false"}
                  class={filter() === tab ? "selected" : ""}
                  onClick={() => setFilter(tab)}
                >
                  {tab}
                </button>
              ))}
            </div>
            <span>
              {
                albums.filter(
                  (a) => filter() === "All releases" || a.category === filter(),
                ).length
              }{" "}
              SELECTED RELEASES
            </span>
          </div>
          <div class="album-grid">
            {albums
              .filter(
                (a) => filter() === "All releases" || a.category === filter(),
              )
              .map((a) => (
                <a
                  class="album"
                  href={musicLink(a.name)}
                  target="_blank"
                  rel="noreferrer"
                >
                  <div class="album-art">
                    <img
                      src={`/images/${a.image}.webp`}
                      alt={`${a.name} album cover`}
                      loading="lazy"
                    />
                    <span class="album-play">
                      <Play size={19} fill="currentColor" />
                    </span>
                  </div>
                  <div class="album-type">
                    {a.type}
                    <ArrowUpRight size={14} />
                  </div>
                  <h3>{a.name}</h3>
                  <p>{a.songs}</p>
                </a>
              ))}
          </div>
        </section>
        <section id="community" class="section wrap community-section">
          <div class="section-heading">
            <div>
              <p class="eyebrow">A LITTLE MORE REMINE</p>
              <h2>
                Your people. Your little universe<span>.</span>
              </h2>
            </div>
            <Heart class="outline-heart" size={33} />
          </div>
          <div class="community-grid">
            <article class="guide-card">
              <img
                src="/images/group.webp"
                alt="RESCENE PULSE group concept"
                loading="lazy"
              />
              <div>
                <span class="small-tag">THE REMINE STARTER PACK</span>
                <h3>
                  Just found RESCENE?
                  <br />
                  You’re in the right place.
                </h3>
                <p>
                  A few songs, a few faces, and the start of something lovely.
                </p>
                <button
                  class="text-link"
                  onClick={() => setModal({ kind: "guide" })}
                >
                  Start your REMINE journey <ArrowRight size={17} />
                </button>
              </div>
            </article>
            <article class="poll-card">
              <div class="poll-heading">
                <span class="eyebrow">ON REPEAT</span>
                <Music2 size={20} />
              </div>
              <h3>
                What’s your
                <br />
                RESCENE soundtrack?
              </h3>
              <p>Pick the track you keep coming back to.</p>
              <div class="poll-options">
                {["LOVE ATTACK", "Glow Up", "Runaway"].map((song) => (
                  <button
                    class={vote() === song ? "voted" : ""}
                    onClick={() => chooseVote(song)}
                    aria-pressed={vote() === song ? "true" : "false"}
                  >
                    <span>{song}</span>
                    {vote() === song ? (
                      <Check size={16} />
                    ) : (
                      <span class="radio-circle" />
                    )}
                  </button>
                ))}
              </div>
              <span class="poll-note">
                {vote()
                  ? `Your pick: ${vote()}. Impeccable taste.`
                  : "Your pick is saved on this device."}
              </span>
            </article>
          </div>
        </section>
        <section class="closing wrap">
          <span class="star">✦</span>
          <p>
            Some moments pass.
            <br />
            <em>This scene stays.</em>
          </p>
          <a
            class="button primary"
            href={official}
            target="_blank"
            rel="noreferrer"
          >
            More moments with RESCENE <ArrowUpRight size={17} />
          </a>
          <span>ALWAYS FIVE. ALWAYS REMINE.</span>
        </section>
      </main>
      <footer class="footer">
        <div class="wrap">
          <div class="footer-top">
            <a class="brand" href="#">
              RE<span>SCENE</span>
              <i>FAN COLLECTIVE</i>
            </a>
            <p>
              An independent little corner of the internet.
              <br />
              Made with love, for RESCENE and REMINE.
            </p>
            <div>
              <a href={official} target="_blank" rel="noreferrer">
                YouTube <ArrowUpRight size={13} />
              </a>
              <a
                href="https://www.instagram.com/rescene_official/"
                target="_blank"
                rel="noreferrer"
              >
                Instagram <ArrowUpRight size={13} />
              </a>
              <a href={musicLink("")} target="_blank" rel="noreferrer">
                Spotify <ArrowUpRight size={13} />
              </a>
            </div>
          </div>
          <div class="footer-bottom">
            <span>© {new Date().getFullYear()} RESCENE Fan Collective</span>
            <p>
              Unofficial fan site. Not affiliated with RESCENE or THE MUZE
              Entertainment.
            </p>
            <button onClick={() => setModal({ kind: "about" })}>
              About & credits <ArrowUpRight size={12} />
            </button>
          </div>
        </div>
      </footer>
      <dialog
        ref={(element) => {
          dialogRef = element;
        }}
        class={`dialog ${search() ? "search-dialog" : ""}`}
        onCancel={close}
        onClick={(e) => {
          if (e.target === e.currentTarget) close();
        }}
        aria-label={
          search()
            ? "Search RESCENE fan site"
            : modal()?.kind === "member"
              ? `${members[memberIndex()].name} profile`
              : modal()?.kind === "quiz"
                ? "RESCENE fan quiz"
                : modal()?.kind === "collection"
                  ? "Your photocard collection"
                  : "RESCENE fan guide"
        }
      >
        <button
          class="dialog-close icon-button"
          aria-label="Close dialog"
          onClick={close}
        >
          <X size={21} />
        </button>
        {search() && (
          <div class="search-content">
            <p class="eyebrow">FIND YOUR SCENE</p>
            <label class="search-input">
              <Search size={21} />
              <input
                autofocus
                value={query()}
                onInput={(e) => setQuery(e.currentTarget.value)}
                placeholder="Members, albums, photocards…"
                aria-label="Search members and albums"
              />
            </label>
            <div class="search-results">
              {searchItems().map((item) => (
                <button onClick={item.action}>
                  <span>
                    {item.title}
                    <small>{item.detail}</small>
                  </span>
                  <ArrowUpRight size={18} />
                </button>
              ))}
              {!searchItems().length && (
                <p>No scenes found. Try a member’s name or an album.</p>
              )}
            </div>
            <span class="poll-note">ESC TO CLOSE</span>
          </div>
        )}
        {modal()?.kind === "member" && (
          <div class="member-detail">
            <img
              src={`/images/${members[memberIndex()].image}.webp`}
              alt={`${members[memberIndex()].name} concept portrait`}
            />
            <div>
              <p class="eyebrow">RESCENE / 0{memberIndex() + 1}</p>
              <h2>
                {members[memberIndex()].name}{" "}
                <small>{members[memberIndex()].korean}</small>
              </h2>
              <h3>{members[memberIndex()].line}</h3>
              <p>{members[memberIndex()].detail}</p>
              <button
                class="button primary"
                onClick={() => collect(members[memberIndex()].image)}
              >
                <Heart
                  size={16}
                  fill={
                    saved().includes(members[memberIndex()].image)
                      ? "currentColor"
                      : "none"
                  }
                />
                {saved().includes(members[memberIndex()].image)
                  ? "Saved to your collection"
                  : "Save this photocard"}
              </button>
              <a
                class="text-link"
                href={official}
                target="_blank"
                rel="noreferrer"
              >
                Watch RESCENE <ExternalLink size={14} />
              </a>
              <span class="poll-note">
                PULSE CONCEPT PORTRAIT · THE MUZE ENTERTAINMENT
              </span>
            </div>
          </div>
        )}
        {modal()?.kind === "collection" && (
          <div class="collection-content">
            <p class="eyebrow">KEEP YOUR FAVORITE SCENES</p>
            <h2>
              Your little collection<span>.</span>
            </h2>
            <p>
              Save the PULSE portraits you love. Your collection stays in this
              browser.
            </p>
            <div class="collection-progress">
              <span>{saved().length} / 5 COLLECTED</span>
              <div>
                <i style={{ width: `${(saved().length / 5) * 100}%` }} />
              </div>
            </div>
            <div class="collection-grid">
              {members.map((m) => (
                <button
                  onClick={() => collect(m.image)}
                  aria-pressed={saved().includes(m.image) ? "true" : "false"}
                  class={saved().includes(m.image) ? "collected" : ""}
                >
                  <img
                    src={`/images/${m.image}.webp`}
                    alt={`${m.name} photocard`}
                  />
                  <span>
                    {m.name}
                    <Heart
                      size={14}
                      fill={saved().includes(m.image) ? "currentColor" : "none"}
                    />
                  </span>
                  <small>
                    {saved().includes(m.image)
                      ? "In your collection"
                      : "Tap to collect"}
                  </small>
                </button>
              ))}
            </div>
          </div>
        )}
        {modal()?.kind === "quiz" && (
          <div class="quiz-content">
            <p class="eyebrow">THE REMINE KNOWLEDGE CHECK</p>
            {step() < questions.length ? (
              <>
                <span class="quiz-count">
                  0{step() + 1} <span>/ 0{questions.length}</span>
                </span>
                <h2>{questions[step()].q}</h2>
                <div class="quiz-choices">
                  {questions[step()].options.map((option, i) => (
                    <button
                      disabled={answers()[step()] !== undefined}
                      class={
                        answers()[step()] === undefined
                          ? ""
                          : i === questions[step()].answer
                            ? "correct"
                            : i === answers()[step()]
                              ? "incorrect"
                              : ""
                      }
                      onClick={() => setAnswers([...answers(), i])}
                    >
                      <span>{String.fromCharCode(65 + i)}</span>
                      {option}
                      {answers()[step()] !== undefined &&
                        i === questions[step()].answer && <Check size={17} />}
                    </button>
                  ))}
                </div>
                {answers()[step()] !== undefined && (
                  <div class="quiz-next">
                    <p>
                      {answers()[step()] === questions[step()].answer
                        ? "You know your scene!"
                        : "One more thing to love about RESCENE."}
                    </p>
                    <button
                      class="button primary"
                      onClick={() => setStep(step() + 1)}
                    >
                      {step() === questions.length - 1
                        ? "See my result"
                        : "Next question"}
                      <ArrowRight size={16} />
                    </button>
                  </div>
                )}
              </>
            ) : (
              <div class="quiz-result">
                <Sparkles size={38} />
                <h2>
                  {answers().filter((a, i) => a === questions[i].answer).length}{" "}
                  / {questions.length}
                </h2>
                <h3>
                  {answers().every((a, i) => a === questions[i].answer)
                    ? "A true scene stealer."
                    : "Your REMINE era has begun."}
                </h3>
                <p>
                  Every favorite song is a good place to start. Keep exploring
                  your scene.
                </p>
                <button class="button primary" onClick={openQuiz}>
                  <RotateCcw size={16} /> Play again
                </button>
              </div>
            )}
          </div>
        )}
        {modal()?.kind === "guide" && (
          <div class="prose-content">
            <p class="eyebrow">YOUR FIRST SCENE</p>
            <h2>
              Welcome to REMINE<span>.</span>
            </h2>
            <p>
              Five members. A world of music. Here’s a little path into RESCENE.
            </p>
            <ol>
              <li>
                <b>Put LOVE ATTACK on repeat.</b>
                <p>
                  Start with SCENEDROME, then explore Glow Up, Dearest, and
                  PULSE in the music library.
                </p>
              </li>
              <li>
                <b>Meet Woni, Liv, Minami, May, and Zena.</b>
                <p>
                  Open the member portraits and save your favorites to your
                  collection. Choosing all five is always an option.
                </p>
              </li>
              <li>
                <b>See the scene for yourself.</b>
                <p>
                  Music videos, performances, and behind-the-scenes moments live
                  on RESCENE’s official YouTube channel.
                </p>
              </li>
            </ol>
            <a
              class="button primary"
              href={official}
              target="_blank"
              rel="noreferrer"
            >
              Visit official YouTube <ArrowUpRight size={17} />
            </a>
          </div>
        )}
        {modal()?.kind === "about" && (
          <div class="prose-content">
            <p class="eyebrow">FROM FANS, WITH LOVE</p>
            <h2>
              About this scene<span>.</span>
            </h2>
            <p>
              RESCENE Fan Collective is an independent fan-made project for
              REMINE. It is not affiliated with RESCENE or THE MUZE
              Entertainment.
            </p>
            <h3>Photography & music</h3>
            <p>
              RESCENE PULSE concept photography and album artwork belong to
              their respective owners. Portraits are from the existing project’s
              PULSE photo archive. Music links open Spotify search, and videos
              link to RESCENE’s official channel.
            </p>
            <a
              class="text-link"
              href="https://kpopping.com/kpics/rescene-4th-mini-album-pulse-concept-photos"
              target="_blank"
              rel="noreferrer"
            >
              PULSE photography source <ExternalLink size={14} />
            </a>
            <h3>Your privacy</h3>
            <p>
              Photocard saves and your song pick are stored only in this
              browser. This site does not create accounts, submit votes to a
              server, or collect email addresses. Remove a saved portrait by
              selecting it again.
            </p>
          </div>
        )}
      </dialog>
    </>
  );
}
