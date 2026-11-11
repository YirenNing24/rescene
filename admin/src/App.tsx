import { createSignal, createMemo, onSettled, For, Show } from "solid-js";
import type { JSX } from "@solidjs/web";
import { api, uid, pretty, date, download, photo, type Row } from "./api";
import { modules, operations, templates, type Module } from "./modules";

const paths: Record<string, string> = {
  grid: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
  users:
    "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M16 3a4 4 0 0 1 0 8 M22 21v-2a4 4 0 0 0-3-3.87 M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0",
  chart: "M3 3v18h18 M7 14l4-5 4 3 5-7",
  heart:
    "M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8",
  bag: "M5 7h14l2 14H3z M9 7V5a3 3 0 0 1 6 0v2",
  box: "m12 3 9 5v10l-9 5-9-5V8z m-9 5 9 5 9-5 M12 13v10 m-4.5-17.5 9 5",
  wallet:
    "M20 8V5H4a2 2 0 0 1 0-4h15 M4 5h16v16H4a2 2 0 0 1-2-2V3 M20 12h-6v5h6",
  code: "m8 7-5 5 5 5 m8-10 5 5-5 5 M14 3l-4 18",
  play: "m8 4 13 8-13 8z",
  music:
    "M9 18V5l12-2v13 M9 9l12-2 M9 18a3 3 0 1 1-3-3c1.7 0 3 1.3 3 3 M21 16a3 3 0 1 1-3-3c1.7 0 3 1.3 3 3",
  trophy:
    "M8 3h8v6a4 4 0 0 1-8 0z M8 5H4v3a4 4 0 0 0 4 4 M16 5h4v3a4 4 0 0 1-4 4 M12 13v7 M8 21h8",
  target: "M21 12a9 9 0 1 1-9-9 M17 12a5 5 0 1 1-5-5 M12 12l9-9 M16 3h5v5",
  calendar: "M3 5h18v16H3z M16 2v6 M8 2v6 M3 11h18",
  spark: "m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5z",
  cards: "m8 2 14 4-4 15-14-4z M4 7l-3 12 13 3",
  layers: "m12 3 10 5-10 5L2 8z M2 12l10 5 10-5 M2 16l10 5 10-5",
  arrows: "M4 7h16l-4-4 M20 17H4l4 4 M20 7v3 M4 17v-3",
  refresh: "M20 7a9 9 0 1 0 1 8 M20 2v6h-6",
  rocket:
    "M12 4c3-2 6-2 9-1 1 4 0 7-3 10l-5 5-7-7z M6 11H2l4-5h4 M13 18v4l5-4v-5 M5 16l-3 6 6-3",
  sliders:
    "M4 21v-7 M4 10V3 M12 21v-9 M12 8V3 M20 21v-3 M20 14V3 M1 10h6 M9 8h6 M17 18h6",
  megaphone: "M3 9h6l12-6v18L9 15H3z M6 15l2 6h4l-3-6",
  image: "M3 3h18v18H3z m0 14 6-6 5 5 3-3 4 4 M8 7h.01",
  shield: "m12 2 9 4v6c0 6-9 10-9 10S3 18 3 12V6z m-5 10 3 3 7-7",
  key: "M14 7a5 5 0 1 1-3-3 M11 11 2 20h4v-3h3v-3l2-3",
  list: "M8 6h13 M8 12h13 M8 18h13 M3 6h.01 M3 12h.01 M3 18h.01",
  pulse: "M2 12h5l3-9 4 18 3-9h5",
  git: "M6 3v12a4 4 0 0 0 4 4h8 M18 5v14 M3 3h6v4H3z M15 2h6v5h-6z M15 17h6v5h-6z",
  clock: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M12 7v5l3 2",
  search: "M21 21l-6-6 M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0",
  arrow: "M5 12h14 m-5-5 5 5-5 5",
  plus: "M12 5v14 M5 12h14",
  x: "m6 6 12 12 M6 18 18 6",
  check: "m5 12 4 4L19 6",
  chevron: "m9 5 7 7-7 7",
  download: "M12 3v12 m-5-5 5 5 5-5 M4 17v4h16v-4",
  logout: "M9 3H3v18h6 M9 12h12 m-5-5 5 5-5 5",
  inbox: "M4 4h16l2 12v5H2v-5z M2 16h6l2 3h4l2-3h6",
  menu: "M3 6h18 M3 12h18 M3 18h18",
};
function Icon(props: { name: string; size?: number }) {
  return (
    <svg
      width={props.size ?? 18}
      height={props.size ?? 18}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.65"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d={paths[props.name] ?? paths.grid} />
    </svg>
  );
}
function Badge(props: { value: any }) {
  return (
    <span
      class={
        "badge " +
        (String(props.value).match(
          /confirmed|active|ready|enabled|published|healthy|true/i,
        )
          ? "green"
          : String(props.value).match(
                /fail|suspend|error|false|closed|missing/i,
              )
            ? "red"
            : "")
      }
    >
      {String(props.value ?? "—").replaceAll("_", " ")}
    </span>
  );
}
function Empty(props: { title?: string; description?: string }) {
  return (
    <div class="empty">
      <span class="empty-icon">
        <Icon name="inbox" size={27} />
      </span>
      <h3>{props.title ?? "Nothing here yet"}</h3>
      <p>
        {props.description ??
          "Records will appear as players and administrators use the game."}
      </p>
    </div>
  );
}
function Modal(props: {
  title: string;
  close: () => void;
  children: JSX.Element;
  wide?: boolean;
}) {
  let el!: HTMLDivElement;
  onSettled(() => {
    el.focus();
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") props.close();
      if (e.key === "Tab") {
        const items = Array.from(
          el.querySelectorAll<HTMLElement>(
            "button,input,select,textarea,a[href]",
          ),
        ).filter((x) => !x.hasAttribute("disabled"));
        if (!items.length) return;
        const first = items[0],
          last = items[items.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  });
  return (
    <div
      class="overlay"
      onClick={(e) => {
        if (e.target === e.currentTarget) props.close();
      }}
    >
      <div
        ref={el}
        class={"modal " + (props.wide ? "wide" : "")}
        role="dialog"
        aria-modal="true"
        aria-label={props.title}
        tabindex={-1}
      >
        <header>
          <div>
            <span class="eyebrow">REMINE OPERATIONS</span>
            <h2>{props.title}</h2>
          </div>
          <button
            class="icon-button"
            aria-label="Close dialog"
            onClick={props.close}
          >
            <Icon name="x" />
          </button>
        </header>
        {props.children}
      </div>
    </div>
  );
}
function Login(props: {
  session: Row | null;
  refresh: () => Promise<void>;
  notice: (s: string) => void;
}) {
  const [email, setEmail] = createSignal("paulanthonyarriola@gmail.com"),
    [key, setKey] = createSignal(""),
    [code, setCode] = createSignal(""),
    [secret, setSecret] = createSignal(""),
    [busy, setBusy] = createSignal(false),
    [error, setError] = createSignal("");
  async function submit(e: SubmitEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      if (props.session) await api("mfa/verify", { code: code() });
      else await api("login", { email: email(), key: key() });
      setKey("");
      await props.refresh();
    } catch (e) {
      setError(String((e as Error).message));
    } finally {
      setBusy(false);
    }
  }
  async function enroll() {
    try {
      const v = await api("mfa/enroll", {});
      setSecret(v.secret);
    } catch (e) {
      setError((e as Error).message);
    }
  }
  return (
    <div class="login">
      <div class="login-art">
        <a class="brand" href="/">
          <span class="brand-mark">r</span>remine
          <span class="brand-suffix">/ ops</span>
        </a>
        <div class="login-copy">
          <span class="eyebrow">THE SPACE BEHIND THE STAGE</span>
          <h1>
            Every player.
            <br />
            Every detail.
            <br />
            <em>One clear view.</em>
          </h1>
          <p>
            Your home for the people, economy and experiences that keep RESCENE
            moving.
          </p>
          <div class="login-orbit">
            <span>R</span>
            <i />
            <i />
            <i />
          </div>
        </div>
        <small>RESCENE RHYTHM · OPERATIONS CONSOLE</small>
      </div>
      <main class="login-panel">
        <div class="login-form">
          <span class="badge green">
            <Icon name="shield" size={13} /> Private workspace
          </span>
          <h2>{props.session ? "One more step." : "Welcome backstage."}</h2>
          <p>
            {props.session
              ? "Verify your authenticator to open the operations console."
              : "Sign in with your administrator email and access key."}
          </p>
          <form onSubmit={submit}>
            {props.session ? (
              <>
                <div class="identity-card">
                  <span class="avatar">PA</span>
                  <div>
                    <strong>{props.session.admin.email}</strong>
                    <small>{props.session.admin.role} administrator</small>
                  </div>
                </div>
                {!props.session.mfa_enrolled ? (
                  <div class="enroll">
                    <h3>Set up an authenticator</h3>
                    <p>
                      Add a time-based account in your authenticator app. Keep
                      the setup key private.
                    </p>
                    {secret() ? (
                      <>
                        <code class="secret">{secret()}</code>
                        <button
                          class="text-button"
                          type="button"
                          onClick={() =>
                            navigator.clipboard
                              .writeText(secret())
                              .then(() => props.notice("Setup key copied"))
                          }
                        >
                          Copy setup key
                        </button>
                      </>
                    ) : (
                      <button type="button" class="secondary" onClick={enroll}>
                        Get setup key <Icon name="key" />
                      </button>
                    )}
                  </div>
                ) : null}
                <label>
                  Authenticator code
                  <input
                    autocomplete="one-time-code"
                    inputmode="numeric"
                    pattern="[0-9]{6}"
                    maxlength={6}
                    value={code()}
                    onInput={(e) => setCode(e.currentTarget.value)}
                    placeholder="000 000"
                    required
                  />
                </label>
              </>
            ) : (
              <>
                <label>
                  Email address
                  <input
                    type="email"
                    autocomplete="username"
                    value={email()}
                    onInput={(e) => setEmail(e.currentTarget.value)}
                    required
                  />
                </label>
                <label>
                  Administrator access key
                  <input
                    type="password"
                    autocomplete="current-password"
                    value={key()}
                    onInput={(e) => setKey(e.currentTarget.value)}
                    placeholder="Enter your private access key"
                    required
                  />
                </label>
              </>
            )}
            {error() ? (
              <p role="alert" class="error">
                {error()}
              </p>
            ) : null}
            <button class="primary full" disabled={busy()}>
              {busy()
                ? "Verifying…"
                : props.session
                  ? "Open workspace"
                  : "Continue securely"}
              <Icon name="arrow" />
            </button>
          </form>
          <p class="login-help">
            Invited administrators only. Access keys and game passwords are
            separate.
          </p>
          <div class="secure-foot">
            <Icon name="shield" size={14} /> Encrypted connection <span>•</span>{" "}
            Authenticator protected
          </div>
        </div>
      </main>
    </div>
  );
}

export default function App() {
  const [session, setSession] = createSignal<Row | null>(null),
    [started, setStarted] = createSignal(false),
    [page, setPage] = createSignal("overview"),
    [data, setData] = createSignal<Row>({}),
    [busy, setBusy] = createSignal(false),
    [error, setError] = createSignal(""),
    [notice, setNotice] = createSignal(""),
    [query, setQuery] = createSignal(""),
    [mobile, setMobile] = createSignal(false),
    [inspect, setInspect] = createSignal<Row | null>(null),
    [profile, setProfile] = createSignal<Row | null>(null),
    [document, setDocument] = createSignal<Row | null>(null),
    [op, setOp] = createSignal<Row | null>(null),
    [invite, setInvite] = createSignal(false),
    [batch, setBatch] = createSignal(false),
    [offset, setOffset] = createSignal(0);
  const current = createMemo(
    () => modules.find((m) => m.id === page()) ?? modules[0],
  );
  const rows = createMemo(() => {
    let v = data().rows;
    if (!Array.isArray(v)) {
      if (Array.isArray(data().products)) v = data().products;
      else if (Array.isArray(data().items)) v = data().items;
      else if (page() === "store")
        v = Object.entries(data())
          .filter(([, x]) => Array.isArray(x))
          .flatMap(([, x]) => x);
      else v = [];
    }
    return (v as Row[]).filter(
      (r) =>
        !query() || pretty(r).toLowerCase().includes(query().toLowerCase()),
    );
  });
  let requestVersion = 0;
  function notify(s: string) {
    setNotice(s);
    setTimeout(() => setNotice(""), 5500);
  }
  async function refreshSession() {
    try {
      setSession(await api("session"));
    } catch {
      setSession(null);
    }
    setStarted(true);
  }
  async function load(id = page(), off = offset(), q = "") {
    const version = ++requestVersion;
    setBusy(true);
    setError("");
    try {
      const m = modules.find((m) => m.id === id)!;
      const v = await api(
        m.path +
          (id === "players" ? `?offset=${off}&q=${encodeURIComponent(q)}` : ""),
      );
      if (["settings", "missions", "calendars"].includes(id))
        v.rules = await api("rules");
      if (version === requestVersion) setData(v);
    } catch (e) {
      if (version === requestVersion) {
        setData({});
        setError((e as Error).message);
      }
    } finally {
      if (version === requestVersion) setBusy(false);
    }
  }
  function go(id: string) {
    setPage(id);
    setOffset(0);
    setQuery("");
    setMobile(false);
    setData({});
    void load(id, 0);
  }
  async function openPlayer(id: string) {
    try {
      setProfile(await api("players/" + id));
    } catch (e) {
      notify((e as Error).message);
    }
  }
  async function refresh() {
    await refreshSession();
    const s = await api("session");
    if (s.admin.mfa) await load();
  }
  onSettled(() => {
    void refreshSession().then(async () => {
      try {
        const s = await api("session");
        if (s.admin.mfa) await load("overview");
      } catch {}
    });
    const timer = setInterval(() => {
      if (documentVisibility() && page() === "overview" && session()?.admin.mfa)
        void load("overview");
    }, 60000);
    return () => clearInterval(timer);
  });
  function documentVisibility() {
    return globalThis.document.visibilityState === "visible";
  }
  const groups = [...new Set(modules.map((m) => m.group))];
  return (
    <>
      {!started() ? (
        <div class="boot">
          <span class="brand-mark">r</span>
          <p>Opening your workspace…</p>
        </div>
      ) : !session()?.admin.mfa ? (
        <Login session={session()} refresh={refresh} notice={notify} />
      ) : (
        <div class="workspace">
          <aside class={"sidebar " + (mobile() ? "mobile-open" : "")}>
            <a
              href="#overview"
              class="brand"
              onClick={(e) => {
                e.preventDefault();
                go("overview");
              }}
            >
              <span class="brand-mark">r</span>remine
              <span class="brand-suffix">/ ops</span>
            </a>
            <button class="workspace-switch">
              <span class="game-mark">R</span>
              <span>
                <strong>RESCENE Rhythm</strong>
                <small>Game operations</small>
              </span>
              <Icon name="chevron" size={14} />
            </button>
            <nav aria-label="Main navigation">
              <For each={groups}>
                {(g) => (
                  <div class="nav-group">
                    <p>{g}</p>
                    <For each={modules.filter((m) => m.group === g)}>
                      {(m) => (
                        <button
                          class={
                            page() === m.id ? "nav-item selected" : "nav-item"
                          }
                          aria-label={m.name}
                          aria-current={page() === m.id ? "page" : undefined}
                          onClick={() => go(m.id)}
                        >
                          <Icon name={m.icon} />
                          <span>{m.name}</span>
                          {m.id === "launch" ? <span class="nav-dot" /> : null}
                          {m.id === "overview" ? (
                            <span class="nav-key">G O</span>
                          ) : null}
                        </button>
                      )}
                    </For>
                  </div>
                )}
              </For>
            </nav>
            <div class="sidebar-bottom">
              <span class="status-dot" />
              <span>{session()?.environment ?? "Elysium Mainnet"}</span>
              <small>{session()?.chain_id === 421614 ? "TESTNET" : "MAINNET"}</small>
            </div>
          </aside>
          <div class="main-shell">
            <header class="topbar">
              <div class="breadcrumbs">
                <button
                  class="icon-button mobile-toggle"
                  onClick={() => setMobile(!mobile())}
                  aria-label="Toggle menu"
                >
                  <Icon name="menu" />
                </button>
                <span>Workspace</span>
                <Icon name="chevron" size={12} />
                <strong>{current().name}</strong>
              </div>
              <div class="top-actions">
                <span class="environment">
                  <span class="status-dot" /> {session()?.environment ?? "Elysium Mainnet"} <span>{session()?.chain_id ?? 99901}</span>
                </span>
                <button class="help-link" onClick={() => go("support")}>
                  Help & support <Icon name="arrow" size={14} />
                </button>
                <span class="divider" />
                <button
                  class="user-button"
                  title={session()?.admin.email}
                  onClick={() => go("team")}
                >
                  <span class="avatar">PA</span>
                  <span>
                    <strong>
                      {session()?.admin.email?.split("@")[0] ?? "Administrator"}
                    </strong>
                    <small>{session()?.admin.role} workspace</small>
                  </span>
                </button>
                <button
                  class="icon-button"
                  title="Sign out"
                  onClick={() => {
                    void api("logout", {}).then(() => {
                      setSession(null);
                      setData({});
                    });
                  }}
                >
                  <Icon name="logout" size={16} />
                </button>
              </div>
            </header>
            <main>
              <div class="page-heading">
                <div>
                  <div class="eyebrow">
                    {current().group === "Workspace"
                      ? "YOUR OPERATIONS, IN SYNC"
                      : current().group.toUpperCase()}
                  </div>
                  <h1>
                    {page() === "overview"
                      ? "A clear view of your game."
                      : current().name}
                  </h1>
                  <p>{current().description}</p>
                </div>
                <div class="heading-actions">
                  <button
                    class="secondary"
                    onClick={() => void load()}
                    disabled={busy()}
                  >
                    <Icon name="refresh" size={15} />
                    {busy() ? "Refreshing…" : "Refresh"}
                  </button>
                  {page() === "overview" ? (
                    <button
                      class="primary"
                      onClick={() =>
                        setOp({ kind: "mint_item", payload: {}, reason: "" })
                      }
                    >
                      <Icon name="plus" size={16} /> Create operation
                    </button>
                  ) : null}
                </div>
              </div>
              {error() ? (
                <div class="error-banner" role="alert">
                  <Icon name="shield" />
                  <span>{error()}</span>
                  <button class="text-button" onClick={() => void load()}>
                    Try again
                  </button>
                </div>
              ) : null}
              {current().note ? (
                <div class="info-banner">
                  <Icon name="inbox" />
                  {current().note}
                </div>
              ) : null}
              {busy() && Object.keys(data()).length === 0 ? (
                <div class="loading">
                  <span class="spinner" /> Loading live records…
                </div>
              ) : page() === "overview" ? (
                <Overview
                  data={data()}
                  go={go}
                  create={() =>
                    setOp({ kind: "mint_item", payload: {}, reason: "" })
                  }
                />
              ) : page() === "analytics" ? (
                <>
                  <div class="kpi-grid">
                    <Metric
                      label="Observed events"
                      value={data().metrics?.events ?? 0}
                      icon="pulse"
                      detail="Most recent 500 mutations"
                    />
                    <Metric
                      label="Unique players"
                      value={data().metrics?.unique_players ?? 0}
                      icon="users"
                      detail="Within this retained window"
                    />
                    <Metric
                      label="Accepted completions"
                      value={data().metrics?.completions ?? 0}
                      icon="trophy"
                      detail="Successful run completion requests"
                    />
                    <Metric
                      label="API errors"
                      value={data().metrics?.errors ?? 0}
                      icon="shield"
                      detail={
                        (data().metrics?.average_latency_ms ?? 0) +
                        " ms average API latency"
                      }
                    />
                  </div>
                  <Records
                    rows={rows()}
                    inspect={setInspect}
                    player={openPlayer}
                  />
                  <p class="source-note">{data().source}</p>
                </>
              ) : page() === "players" ? (
                <>
                  <div class="section-toolbar">
                    <form
                      class="search-field"
                      onSubmit={(e) => {
                        e.preventDefault();
                        void load("players", 0, query());
                      }}
                    >
                      <Icon name="search" />
                      <input
                        aria-label="Search players"
                        value={query()}
                        onInput={(e) => setQuery(e.currentTarget.value)}
                        placeholder="Search by username, ID or wallet…"
                      />
                      <button class="text-button">Search</button>
                    </form>
                    <span class="muted">
                      {rows().length} players on this page
                    </span>
                  </div>
                  <div class="player-grid">
                    <For each={rows()}>
                      {(r) => (
                        <button
                          class="player-card"
                          onClick={() => void openPlayer(r.id)}
                        >
                          <div class="player-card-top">
                            {r.media?.avatar ? (
                              <img
                                class="player-avatar"
                                src={
                                  "/api/players/" +
                                  r.id +
                                  "/media/" +
                                  r.media.avatar
                                }
                                alt=""
                              />
                            ) : (
                              <span class="player-avatar initials">
                                {r.username?.slice(0, 2).toUpperCase()}
                              </span>
                            )}
                            <Badge value={r.status} />
                          </div>
                          <h3>{r.username}</h3>
                          <span class="mono muted">{r.id?.slice(0, 12)}…</span>
                          <div class="player-stat">
                            <span>
                              <strong>{r.progression?.xp ?? 0}</strong> XP
                            </span>
                            <span>
                              <strong>{r.progression?.clears ?? 0}</strong>{" "}
                              clears
                            </span>
                          </div>
                          <footer>
                            View player profile <Icon name="arrow" size={16} />
                          </footer>
                        </button>
                      )}
                    </For>
                  </div>
                  {!rows().length ? (
                    <Empty
                      title="No players found"
                      description="Try a different username or player ID."
                    />
                  ) : null}
                  <div class="pagination">
                    <button
                      class="secondary"
                      disabled={!offset()}
                      onClick={() => {
                        const n = Math.max(0, offset() - 50);
                        setOffset(n);
                        void load("players", n, query());
                      }}
                    >
                      Previous
                    </button>
                    <span>Page {Math.floor(offset() / 50) + 1}</span>
                    <button
                      class="secondary"
                      disabled={!data().has_more}
                      onClick={() => {
                        const n = offset() + 50;
                        setOffset(n);
                        void load("players", n, query());
                      }}
                    >
                      Next
                    </button>
                  </div>
                </>
              ) : page() === "settings" ? (
                <Settings
                  data={data()}
                  saved={() => {
                    notify("Game controls published");
                    void load();
                  }}
                />
              ) : page() === "treasury" ? (
                <Treasury
                  data={data()}
                  create={(kind) => setOp({ kind, payload: {}, reason: "" })}
                />
              ) : page() === "team" ? (
                <>
                  <div class="section-toolbar">
                    <span class="muted">
                      Access is checked on every request. Six scoped roles
                      available.
                    </span>
                    <button class="primary" onClick={() => setInvite(true)}>
                      <Icon name="plus" /> Invite administrator
                    </button>
                  </div>
                  <Records rows={rows()} inspect={setInspect} />
                </>
              ) : page() === "monitoring" ? (
                <>
                  <div class="health-grid">
                    <For each={data().rows ?? []}>
                      {(r) => (
                        <div class="panel health-card">
                          <Icon name="pulse" />
                          <h3>{r.name}</h3>
                          <Badge value={r.status} />
                          {r.latency_ms !== undefined ? (
                            <p class="muted">{r.latency_ms} ms database ping</p>
                          ) : null}
                        </div>
                      )}
                    </For>
                  </div>
                </>
              ) : page() === "launch" ? (
                <Launch
                  data={data()}
                  create={() =>
                    setDocument({
                      group: "supply-policy",
                      name: "PULSE supply and reissue policy",
                      status: "draft",
                      revision: 0,
                      value: {
                        per_member_cap: null,
                        reissue_policy: "undecided",
                        requires_contract_release: true,
                      },
                    })
                  }
                />
              ) : (
                <>
                  <div class="section-toolbar">
                    <div class="search-field">
                      <Icon name="search" />
                      <input
                        aria-label="Filter records"
                        value={query()}
                        onInput={(e) => setQuery(e.currentTarget.value)}
                        placeholder="Filter these records…"
                      />
                    </div>
                    <div class="toolbar-actions">
                      <button
                        class="secondary"
                        onClick={() => download(data(), "remine-" + page())}
                      >
                        <Icon name="download" size={15} /> Export JSON
                      </button>
                      {current().document ? (
                        <button
                          class="primary"
                          onClick={() =>
                            setDocument({
                              group: current().document,
                              name: "",
                              status: "draft",
                              revision: 0,
                              value: templates[current().document!] ?? {},
                            })
                          }
                        >
                          <Icon name="plus" size={16} /> Create record
                        </button>
                      ) : null}
                      {page() === "minting" ? (
                        <button
                          class="primary"
                          onClick={() =>
                            setOp({
                              kind: "mint_item",
                              payload: {},
                              reason: "",
                            })
                          }
                        >
                          <Icon name="plus" size={16} /> Prepare mint
                        </button>
                      ) : null}
                      {page() === "minting" ? (
                        <button
                          class="secondary"
                          onClick={() => setBatch(true)}
                        >
                          Import mint CSV <Icon name="download" size={15} />
                        </button>
                      ) : null}
                      {page() === "media" ? (
                        <label class="primary file-button">
                          <Icon name="plus" /> Upload image
                          <input
                            type="file"
                            accept="image/jpeg,image/png"
                            onChange={async (e) => {
                              const f = e.currentTarget.files?.[0];
                              if (!f) return;
                              try {
                                const r = await fetch("/api/assets", {
                                  method: "POST",
                                  headers: { "Content-Type": f.type },
                                  body: f,
                                });
                                const j = await r.json();
                                if (!r.ok)
                                  throw new Error(
                                    j.error?.message ?? "Upload failed",
                                  );
                                notify("Image stored privately");
                                void load();
                              } catch (e) {
                                notify((e as Error).message);
                              }
                            }}
                          />
                        </label>
                      ) : null}
                    </div>
                  </div>
                  {data().source ? (
                    <p class="source-note">{data().source}</p>
                  ) : null}
                  <Records
                    rows={rows()}
                    inspect={(r) => {
                      if (current().document)
                        setDocument({ ...r, group: current().document });
                      else setInspect(r);
                    }}
                    player={openPlayer}
                    actions={(r) => {
                      if (page() === "leaderboards")
                        setOp({
                          kind: r.quarantined
                            ? "restore_score"
                            : "quarantine_score",
                          payload: { score_id: r.id },
                          reason: "",
                        });
                      else if (page() === "recovery")
                        setOp({
                          kind: "retry_job",
                          payload: { job_type: r.type, job_id: r.id },
                          reason: "",
                        });
                      else if (page() === "minting") setOp({ ...r });
                      else setInspect(r);
                    }}
                    actionLabel={
                      page() === "leaderboards"
                        ? "Moderate"
                        : page() === "recovery"
                          ? "Wake job"
                          : page() === "minting"
                            ? "Review"
                            : undefined
                    }
                  />
                  {page() === "missions" || page() === "calendars" ? (
                    <section class="panel current-rules">
                      <div class="panel-heading">
                        <div>
                          <h2>Current game definitions</h2>
                          <p>{data().rules?.source}</p>
                        </div>
                        <Badge value="Compiled rules" />
                      </div>
                      <Records
                        rows={
                          data().rules?.[
                            page() === "missions" ? "missions" : "calendar"
                          ] ?? []
                        }
                        inspect={setInspect}
                      />
                    </section>
                  ) : null}
                  {page() === "media" ? (
                    <div class="photo-grid media-grid">
                      <For each={rows()}>
                        {(r) => (
                          <div class="panel modal-content">
                            <img src={r.value?.path} alt={r.name} />
                            <h3>{r.name}</h3>
                            <code>{r.value?.content_hash}</code>
                          </div>
                        )}
                      </For>
                    </div>
                  ) : null}
                  {page() === "contracts" ? (
                    <div class="info-banner">
                      <Icon name="code" />
                      {data().immutable}
                    </div>
                  ) : null}
                  {page() === "refinement" ? <SkillGuide /> : null}
                </>
              )}
              <footer class="page-footer">
                <span>
                  <span class="status-dot" />
                  {error()
                    ? "API connection needs attention"
                    : busy()
                      ? "Refreshing game records…"
                      : "Connected to the game API"}
                </span>
                <span>
                  {date(data().fresh_at ?? data().checked_at)} · RESCENE
                  Operations v1.0
                </span>
              </footer>
            </main>
          </div>
        </div>
      )}
      {notice() ? (
        <div class="toast" role="status">
          <Icon name="check" />
          {notice()}
        </div>
      ) : null}
      {inspect() ? (
        <Modal
          title={inspect()!.name ?? inspect()!.kind ?? "Record detail"}
          close={() => setInspect(null)}
          wide
        >
          <div class="modal-content">
            {inspect()!.player_id ? (
              <button
                class="secondary"
                onClick={() => {
                  void openPlayer(inspect()!.player_id);
                  setInspect(null);
                }}
              >
                Open player profile <Icon name="arrow" />
              </button>
            ) : null}
            {inspect()!.address &&
            String(inspect()!.address).startsWith("0x") && inspect()!.explorer ? (
              <a
                class="text-button"
                href={
                  String(inspect()!.explorer)
                }
                target="_blank"
                rel="noreferrer"
              >
                View contract on explorer ↗
              </a>
            ) : null}
            <pre>{pretty(inspect())}</pre>
            {inspect()!.document ? (
              <button
                class="secondary"
                onClick={async () => {
                  try {
                    const old = inspect()!;
                    const [group, id] = String(old.document).split("/");
                    const response = await api("documents/" + group);
                    const current = response.rows.find((d: Row) => d.id === id);
                    if (!current)
                      throw new Error("The document is no longer available.");
                    setDocument({
                      group,
                      id,
                      name: old.name,
                      status: "draft",
                      revision: current.revision,
                      value: old.value,
                    });
                    setInspect(null);
                  } catch (e) {
                    notify((e as Error).message);
                  }
                }}
              >
                Restore as reviewed draft <Icon name="refresh" size={15} />
              </button>
            ) : null}
            {inspect()!.kind && operations[inspect()!.kind] ? (
              <button
                class="primary"
                onClick={() => {
                  setOp(inspect());
                  setInspect(null);
                }}
              >
                Review operation
              </button>
            ) : null}
          </div>
        </Modal>
      ) : null}
      {profile() ? (
        <PlayerProfile
          data={profile()!}
          close={() => setProfile(null)}
          create={(v) => {
            setProfile(null);
            setOp(v);
          }}
          open={openPlayer}
          notify={notify}
        />
      ) : null}
      {document() ? (
        <DocumentEditor
          data={document()!}
          close={() => setDocument(null)}
          saved={() => {
            setDocument(null);
            notify("Versioned record saved");
            void load();
          }}
        />
      ) : null}
      {op() ? (
        <Operation
          data={op()!}
          network={session()?.environment ?? "Elysium Mainnet"}
          chainId={session()?.chain_id ?? 99901}
          close={() => setOp(null)}
          saved={() => {
            notify("Operation updated");
            void load();
          }}
        />
      ) : null}
      {batch() ? (
        <BatchMint
          close={() => setBatch(false)}
          saved={() => {
            notify("Mint intents prepared for individual review");
            void load();
          }}
        />
      ) : null}
      {invite() ? (
        <Invite close={() => setInvite(false)} saved={() => void load()} />
      ) : null}
    </>
  );
}

function Overview(props: {
  data: Row;
  go: (s: string) => void;
  create: () => void;
}) {
  const counts = () => props.data.counts ?? {},
    totals = () => props.data.totals ?? {};
  const today = new Date();
  const days = Array.from({ length: 14 }, (_, i) => {
    const d = new Date(today);
    d.setDate(d.getDate() - 13 + i);
    return d.toISOString().slice(0, 10);
  });
  const max = createMemo(() =>
    Math.max(1, ...days.map((d) => props.data.registration_days?.[d] ?? 0)),
  );
  return (
    <>
      <div class="overview-strip">
        <span class="live-label">
          <span class="status-dot" /> LIVE WORKSPACE
        </span>
        <span>Small details. Better player experiences.</span>
        <button onClick={() => props.go("monitoring")}>
          View system health <Icon name="arrow" size={15} />
        </button>
      </div>
      <div class="kpi-grid">
        <Metric
          label="Total players"
          value={counts().players ?? "—"}
          icon="users"
          detail="Registered game accounts"
        />
        <Metric
          label="Online now"
          value={counts().online ?? "—"}
          icon="pulse"
          detail="Presence within 90 seconds"
        />
        <Metric
          label="Recorded clears"
          value={totals().clears ?? "—"}
          icon="trophy"
          detail={`Across ${props.data.players_scanned ?? 0} retained profiles`}
        />
        <Metric
          label="Store orders"
          value={counts().orders ?? "—"}
          icon="bag"
          detail={`${counts().pending_orders ?? 0} awaiting completion`}
        />
      </div>
      <div class="overview-middle">
        <section class="panel activity-panel">
          <div class="panel-heading">
            <div>
              <h2>Player growth</h2>
              <p>A little more rhythm, every day.</p>
            </div>
            <span class="select-label">
              Last 14 days <Icon name="chevron" size={12} />
            </span>
          </div>
          <div class="chart-legend">
            <span class="legend-dot" /> New player registrations{" "}
            <span>UTC dates</span>
          </div>
          <div class="growth-chart">
            <div class="chart-axis">
              <span>{max()}</span>
              <span>{Math.ceil(max() / 2)}</span>
              <span>0</span>
            </div>
            <div class="chart-plot">
              <div class="grid-line l1" />
              <div class="grid-line l2" />
              <div class="grid-line l3" />
              <For each={days}>
                {(d, i) => (
                  <div
                    class="chart-col"
                    title={
                      d +
                      ": " +
                      (props.data.registration_days?.[d] ?? 0) +
                      " registrations"
                    }
                  >
                    <div
                      class="bar"
                      style={{
                        height:
                          Math.max(
                            2,
                            ((props.data.registration_days?.[d] ?? 0) / max()) *
                              100,
                          ) + "%",
                      }}
                    />
                    {i() % 3 === 0 ? (
                      <span>
                        {new Date(d + "T00:00:00").toLocaleDateString(
                          undefined,
                          { month: "short", day: "numeric" },
                        )}
                      </span>
                    ) : null}
                  </div>
                )}
              </For>
            </div>
          </div>
          <footer class="chart-footer">
            <span>
              <Icon name="users" size={14} /> Real registrations from retained
              account data
            </span>
            <button class="text-button" onClick={() => props.go("analytics")}>
              Explore analytics <Icon name="arrow" size={14} />
            </button>
          </footer>
        </section>
        <section class="launch-card">
          <div class="launch-card-top">
            <span class="badge">NEXT ON STAGE</span>
            <Icon name="spark" size={24} />
          </div>
          <h2>
            Make room
            <br />
            for PULSE.
          </h2>
          <p>A careful launch starts with the right foundations.</p>
          <div class="launch-progress">
            <span />
            <span />
            <span />
            <span />
            <span />
          </div>
          <div class="launch-card-note">
            <Icon name="shield" size={16} />
            <span>Sales closed · readiness review</span>
          </div>
          <button onClick={() => props.go("launch")}>
            Open launch console <Icon name="arrow" size={17} />
          </button>
          <div class="orbit-decoration" />
        </section>
      </div>
      <div class="overview-bottom">
        <section class="panel queue-panel">
          <div class="panel-heading">
            <div>
              <h2>Needs your attention</h2>
              <p>The next things to keep moving.</p>
            </div>
            <span class="round-icon">
              <Icon name="inbox" />
            </span>
          </div>
          <For
            each={[
              {
                name: "STARL payouts",
                value: counts().pending_payouts,
                icon: "wallet",
                page: "transactions",
                detail: "Pending chain confirmation",
              },
              {
                name: "Score publications",
                value: counts().pending_scores,
                icon: "trophy",
                page: "recovery",
                detail: "Original verified score jobs",
              },
              {
                name: "Proposed operations",
                value: counts().proposals,
                icon: "layers",
                page: "minting",
                detail: "Waiting for operator review",
              },
              {
                name: "Open moderation reports",
                value: counts().reports,
                icon: "shield",
                page: "moderation",
                detail: "Player and community cases",
              },
            ]}
          >
            {(v) => (
              <button class="queue-row" onClick={() => props.go(v.page)}>
                <span class={"queue-icon " + v.icon}>
                  <Icon name={v.icon} />
                </span>
                <span>
                  <strong>{v.name}</strong>
                  <small>{v.detail}</small>
                </span>
                <b>{v.value ?? "—"}</b>
                <Icon name="chevron" size={15} />
              </button>
            )}
          </For>
        </section>
        <section class="panel shortcuts-panel">
          <div class="panel-heading">
            <div>
              <h2>Your daily toolkit</h2>
              <p>A direct line to the details.</p>
            </div>
            <Icon name="grid" />
          </div>
          <div class="shortcuts">
            <For
              each={[
                {
                  name: "Find a player",
                  detail: "Profiles, friends & gallery",
                  icon: "users",
                  page: "players",
                },
                {
                  name: "Manage the store",
                  detail: "Catalog & live availability",
                  icon: "bag",
                  page: "store",
                },
                {
                  name: "Prepare a mint",
                  detail: "Validate before signing",
                  icon: "plus",
                  page: "minting",
                },
                {
                  name: "Game controls",
                  detail: "Live operational switches",
                  icon: "sliders",
                  page: "settings",
                },
              ]}
            >
              {(s) => (
                <button onClick={() => props.go(s.page)}>
                  <span>
                    <Icon name={s.icon} size={21} />
                  </span>
                  <strong>{s.name}</strong>
                  <small>{s.detail}</small>
                  <Icon name="arrow" size={15} />
                </button>
              )}
            </For>
          </div>
        </section>
      </div>
      <div class="data-note">
        <Icon name="clock" size={15} />
        <span>
          Telemetry begins at deployment. Progression totals scan up to{" "}
          {props.data.aggregation_limit ?? 1000} profiles; historical retention
          metrics are unavailable.
        </span>
      </div>
    </>
  );
}
function Metric(props: {
  label: string;
  value: any;
  icon: string;
  detail: string;
}) {
  return (
    <div class="metric">
      <div>
        <span>{props.label}</span>
        <span class="metric-icon">
          <Icon name={props.icon} />
        </span>
      </div>
      <strong>
        {typeof props.value === "number"
          ? props.value.toLocaleString()
          : props.value}
      </strong>
      <small>{props.detail}</small>
    </div>
  );
}
function Records(props: {
  rows: Row[];
  inspect: (r: Row) => void;
  player?: (id: string) => void;
  actions?: (r: Row) => void;
  actionLabel?: string;
}) {
  const columns = createMemo(() => {
    const keys = [...new Set(props.rows.flatMap((r) => Object.keys(r)))];
    return keys
      .filter(
        (k) =>
          !["payload", "result", "value", "args", "abi", "data"].includes(k),
      )
      .slice(0, 7);
  });
  function cell(r: Row, k: string) {
    const v = r[k];
    if (k === "player_id" && props.player)
      return (
        <button class="table-link mono" onClick={() => props.player!(v)}>
          {String(v ?? "").slice(0, 10)}…
        </button>
      );
    if (
      [
        "status",
        "role",
        "configured",
        "quarantined",
        "enabled",
        "relationship",
      ].includes(k)
    )
      return <Badge value={v} />;
    if (k === "at" || k.endsWith("_at")) return date(v);
    if (typeof v === "object")
      return v === null
        ? "—"
        : Array.isArray(v)
          ? `${v.length} entries`
          : Object.keys(v).slice(0, 3).join(", ");
    return (
      <span
        class={k === "id" || k.includes("address") ? "mono" : ""}
        title={String(v ?? "")}
      >
        {String(v ?? "—").length > 62
          ? String(v).slice(0, 54) + "…"
          : String(v ?? "—")}
      </span>
    );
  }
  return (
    <div class="panel records">
      {props.rows.length ? (
        <>
          <div class="table-scroll">
            <table>
              <thead>
                <tr>
                  <For each={columns()}>
                    {(k) => <th>{k.replaceAll("_", " ")}</th>}
                  </For>
                  <th class="align-right">Details</th>
                </tr>
              </thead>
              <tbody>
                <For each={props.rows}>
                  {(r) => (
                    <tr>
                      <For each={columns()}>{(k) => <td>{cell(r, k)}</td>}</For>
                      <td class="align-right">
                        {props.actionLabel ? (
                          <button
                            class="table-link"
                            onClick={() => props.actions?.(r)}
                          >
                            {props.actionLabel}
                          </button>
                        ) : null}
                        <button
                          class="icon-button"
                          aria-label="Inspect record"
                          onClick={() => props.inspect(r)}
                        >
                          <Icon name="arrow" size={15} />
                        </button>
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
          <div class="table-footer">
            {props.rows.length} records · limited to the most recent retained
            data
          </div>
        </>
      ) : (
        <Empty />
      )}
    </div>
  );
}
function Settings(props: { data: Row; saved: () => void }) {
  const [flags, setFlags] = createSignal<Row>({}),
    [reason, setReason] = createSignal(""),
    [busy, setBusy] = createSignal(false),
    [err, setErr] = createSignal("");
  onSettled(() => {
    const r: Row = {};
    for (const d of [...(props.data.rows ?? [])].reverse())
      if (d.status === "published") Object.assign(r, d.value);
    setFlags(r);
  });
  const labels: Record<string, [string, string]> = {
    maintenance: [
      "Maintenance mode",
      "Block new player mutations while investigating an incident.",
    ],
    purchases_paused: [
      "Pause purchases",
      "Stop new purchases through the game API.",
    ],
    runs_paused: [
      "Pause new runs",
      "Keep existing runs available for completion.",
    ],
    uploads_paused: [
      "Pause photo uploads",
      "Prevent new avatar and gallery uploads.",
    ],
    social_paused: [
      "Pause social interactions",
      "Pause follow, presence and messaging mutations.",
    ],
  };
  async function save(e: SubmitEvent) {
    e.preventDefault();
    setBusy(true);
    setErr("");
    try {
      const v: Row = {};
      for (const k in labels) v[k] = flags()[k] === true;
      await api("documents/settings", {
        name: "Live game controls",
        status: "published",
        revision: 0,
        reason: reason(),
        value: v,
      });
      props.saved();
    } catch (e) {
      setErr((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <form class="panel settings-panel" onSubmit={save}>
      <div class="panel-heading">
        <div>
          <h2>Live game controls</h2>
          <p>Published changes take effect within three seconds.</p>
        </div>
        <Badge value="Live API" />
      </div>
      <For each={Object.entries(labels)}>
        {([k, v]) => (
          <label class="switch-row">
            <span>
              <strong>{v[0]}</strong>
              <small>{v[1]}</small>
            </span>
            <input
              type="checkbox"
              checked={flags()[k] === true}
              onChange={(e) =>
                setFlags({ ...flags(), [k]: e.currentTarget.checked })
              }
            />
          </label>
        )}
      </For>
      <div class="settings-footer">
        <label>
          Reason for this change
          <input
            minlength={8}
            required
            placeholder="Explain the operational reason…"
            value={reason()}
            onInput={(e) => setReason(e.currentTarget.value)}
          />
        </label>
        {err() ? <p class="error">{err()}</p> : null}
        <button class="primary" disabled={busy()}>
          Publish game controls <Icon name="check" size={16} />
        </button>
      </div>
      <div class="settings-footer">
        <h3>Current compiled economy rules</h3>
        <p>{props.data.rules?.source}</p>
        <pre>{pretty(props.data.rules?.energy)}</pre>
        <details>
          <summary>Inspect XP level curve</summary>
          <pre>{pretty(props.data.rules?.levels)}</pre>
        </details>
      </div>
    </form>
  );
}
function Treasury(props: { data: Row; create: (s: string) => void }) {
  return (
    <>
      <div class="kpi-grid three">
        <Metric
          icon="wallet"
          label="Treasury STARL"
          value={props.data.starlight_balance ?? "—"}
          detail="Live ERC-20 balance"
        />
        <Metric
          icon="layers"
          label="Total STARL supply"
          value={props.data.total_supply ?? "—"}
          detail="On-chain total supply"
        />
        <Metric
          icon="pulse"
          label="Native gas (wei, hex)"
          value={props.data.gas_balance_hex ?? "—"}
          detail={props.data.chain_id === 421614 ? "Arbitrum Sepolia ETH" : "Elysium HYPE"}
        />
      </div>
      <div class="panel treasury-panel">
        <h2>Operator wallet</h2>
        <code>{props.data.treasury ?? "RPC data unavailable"}</code>
        <div class="toolbar-actions">
          <button
            class="primary"
            onClick={() => props.create("transfer_starl")}
          >
            Prepare transfer <Icon name="arrow" />
          </button>
          <button
            class="secondary"
            onClick={() => props.create("compensate_starl")}
          >
            Player compensation
          </button>
          <button
            class="secondary"
            onClick={() => props.create("approve_allowance")}
          >
            Bounded allowance
          </button>
        </div>
        <p class="muted">
          Every write is simulated and requires explicit confirmation. Check the
          selected network, recipient and amount before submitting.
        </p>
      </div>
    </>
  );
}
function Launch(props: { data: Row; create: () => void }) {
  return (
    <div class="panel launch-checks">
      <div class="panel-heading">
        <div>
          <h2>PULSE VERSION 2</h2>
          <p>Review every launch dependency before opening sales.</p>
        </div>
        <Badge value="Sales closed" />
      </div>
      <Records
        rows={
          props.data.rows ??
          Object.entries(props.data).map(([name, status]) => ({
            name,
            status: typeof status === "object" ? pretty(status) : status,
          }))
        }
        inspect={() => {}}
      />
      <div class="modal-content">
        <div class="info-banner">
          <Icon name="shield" />A supply-cap contract release and artwork
          reissue rules are still required. The admin will not open unlimited
          sales.
        </div>
        <button class="primary" onClick={props.create}>
          Draft supply policy <Icon name="arrow" />
        </button>
      </div>
    </div>
  );
}
function SkillGuide() {
  return (
    <div class="panel modal-content">
      <h2>Permanent skill rules</h2>
      <p>
        Card skills and base rolls are immutable. Refinement and stars never
        reroll a card. The six-skill definitions are compiled with gameplay and
        require a coordinated release to change.
      </p>
      <div class="info-banner">
        <Icon name="shield" />
        Run-bound decks preserve verification and ownership reservations.
        Administrative inspection does not bypass player locks.
      </div>
    </div>
  );
}
function PlayerProfile(props: {
  data: Row;
  close: () => void;
  create: (v: Row) => void;
  open: (id: string) => void;
  notify: (s: string) => void;
}) {
  const [tab, setTab] = createSignal("Profile"),
    [inventory, setInventory] = createSignal<Row | null>(null),
    [notes, setNotes] = createSignal(""),
    [busy, setBusy] = createSignal(false);
  const id = () => props.data.user.id;
  function action(kind: string, payload: Row = {}) {
    props.create({
      kind,
      payload: { player_id: id(), ...payload },
      reason: "",
    });
  }
  async function getInventory() {
    setTab("Inventory");
    setBusy(true);
    try {
      setInventory(await api("players/" + id() + "/inventory"));
    } catch (e) {
      props.notify((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title="Player profile" close={props.close} wide>
      <div class="profile-cover">
        <div class="profile-orbit" />
        <div class="profile-identity">
          {props.data.media?.avatar ? (
            <img
              class="profile-avatar"
              src={photo(props.data.media.avatar.url)}
              alt="Player avatar"
            />
          ) : (
            <span class="profile-avatar initials">
              {props.data.user.username.slice(0, 2).toUpperCase()}
            </span>
          )}
          <div>
            <h2>{props.data.user.username}</h2>
            <code>{id()}</code>
          </div>
          <Badge value="Game player" />
        </div>
      </div>
      <div class="profile-tabs">
        <For
          each={[
            "Profile",
            "Progression",
            "Records",
            "Friends",
            "Photos",
            "Inventory",
            "Sessions",
            "Support",
          ]}
        >
          {(t) => (
            <button
              class={tab() === t ? "active" : ""}
              onClick={() =>
                t === "Inventory" ? void getInventory() : setTab(t)
              }
            >
              {t}
            </button>
          )}
        </For>
      </div>
      <div class="modal-content">
        {tab() === "Profile" ? (
          <>
            <div class="profile-metrics">
              <Metric
                label="Total XP"
                value={props.data.raw_progression?.xp ?? 0}
                detail="Game progression"
                icon="spark"
              />
              <Metric
                label="Clears"
                value={props.data.raw_progression?.clears ?? 0}
                detail="Retained lifetime total"
                icon="trophy"
              />
              <Metric
                label="Friends"
                value={props.data.social_counts?.friends ?? 0}
                detail="Mutual follows"
                icon="users"
              />
            </div>
            <dl class="detail-list">
              <dt>Joined</dt>
              <dd>{date(props.data.user.created_at)}</dd>
              <dt>Wallet</dt>
              <dd class="mono">
                {props.data.wallet?.address ?? "Not provisioned"}
              </dd>
              <dt>Followers</dt>
              <dd>{props.data.social_counts?.followers ?? 0}</dd>
              <dt>Following</dt>
              <dd>{props.data.social_counts?.following ?? 0}</dd>
            </dl>
          </>
        ) : tab() === "Friends" ? (
          <>
            <p class="muted">
              Mutual follows are friends. Source identifies the direction of
              each follow or block.
            </p>
            <Records
              rows={props.data.relationships ?? []}
              inspect={(r) => props.open(r.id)}
              player={props.open}
            />
          </>
        ) : tab() === "Photos" ? (
          <>
            <div class="info-banner">
              <Icon name="image" />
              Players can use an avatar and up to five gallery pictures.
              Moderators can review quarantined media here.
            </div>
            <div class="photo-grid">
              <For
                each={[
                  props.data.media?.avatar,
                  ...(props.data.media?.gallery ?? []),
                ].filter(Boolean)}
              >
                {(p) => (
                  <div>
                    <img src={photo(p.url)} alt="Player uploaded photo" />
                    <code>{p.id}</code>
                    <div class="toolbar-actions">
                      <button
                        class="secondary"
                        onClick={() =>
                          action("quarantine_photo", { photo_id: p.id })
                        }
                      >
                        Quarantine
                      </button>
                      <button
                        class="text-button"
                        onClick={() =>
                          action("restore_photo", { photo_id: p.id })
                        }
                      >
                        Restore
                      </button>
                    </div>
                  </div>
                )}
              </For>
            </div>
          </>
        ) : tab() === "Records" ? (
          <Records
            rows={props.data.records ?? []}
            inspect={(r) => props.notify(pretty(r))}
          />
        ) : tab() === "Sessions" ? (
          <>
            <p class="muted">
              Session secrets are never displayed. Revocation also invalidates
              existing player access tokens.
            </p>
            <Records rows={props.data.sessions ?? []} inspect={() => {}} />
            <button class="secondary" onClick={() => action("revoke_sessions")}>
              Revoke all sessions
            </button>
          </>
        ) : tab() === "Inventory" ? (
          busy() ? (
            <div class="loading">Reading confirmed ownership…</div>
          ) : (
            <pre>{pretty(inventory())}</pre>
          )
        ) : tab() === "Support" ? (
          <>
            <h3>Account and progression actions</h3>
            <div class="support-actions">
              <For
                each={[
                  "suspend",
                  "restore",
                  "revoke_sessions",
                  "restrict_uploads",
                  "restrict_social",
                  "grant_xp",
                  "grant_energy",
                ]}
              >
                {(k) => (
                  <button
                    class="secondary"
                    onClick={() => action(k, operations[k].initial ?? {})}
                  >
                    {operations[k].name}
                    <Icon name="arrow" size={14} />
                  </button>
                )}
              </For>
            </div>
            <form
              onSubmit={async (e) => {
                e.preventDefault();
                try {
                  await api("documents/notes", {
                    name: "Player note: " + props.data.user.username,
                    status: "published",
                    revision: 0,
                    reason: "Player support investigation note",
                    value: { player_id: id(), note: notes() },
                  });
                  setNotes("");
                  props.notify("Internal support note saved");
                } catch (e) {
                  props.notify((e as Error).message);
                }
              }}
            >
              <label>
                Internal support note
                <textarea
                  required
                  value={notes()}
                  onInput={(e) => setNotes(e.currentTarget.value)}
                  placeholder="Record the investigation, evidence and next action…"
                />
              </label>
              <button class="primary">Save internal note</button>
            </form>
          </>
        ) : (
          <pre>{pretty(props.data.progression)}</pre>
        )}
      </div>
    </Modal>
  );
}
function DocumentEditor(props: {
  data: Row;
  close: () => void;
  saved: () => void;
}) {
  const [name, setName] = createSignal(""),
    [status, setStatus] = createSignal("draft"),
    [value, setValue] = createSignal("{}"),
    [reason, setReason] = createSignal(""),
    [error, setError] = createSignal(""),
    [busy, setBusy] = createSignal(false);
  onSettled(() => {
    setName(props.data.name ?? "");
    setStatus(props.data.status ?? "draft");
    setValue(pretty(props.data.value ?? {}));
  });
  async function submit(e: SubmitEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const v = JSON.parse(value());
      if (typeof v !== "object" || Array.isArray(v) || v === null)
        throw new Error("The value must be a JSON object.");
      await api("documents/" + props.data.group, {
        id: props.data.id,
        name: name(),
        status: status(),
        revision: props.data.revision ?? 0,
        reason: reason(),
        value: v,
      });
      props.saved();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal
      title={"Edit " + props.data.group + " record"}
      close={props.close}
      wide
    >
      <form class="modal-content" onSubmit={submit}>
        <div class="info-banner">
          <Icon name="git" />
          Revision {props.data.revision ?? 0}. Saving preserves the previous
          value. Published content remains an administrative record until its
          game integration is released.
        </div>
        <div class="form-grid">
          <label>
            Name
            <input
              value={name()}
              minlength={2}
              maxlength={120}
              required
              onInput={(e) => setName(e.currentTarget.value)}
            />
          </label>
          <label>
            Status
            <select
              value={status()}
              onChange={(e) => setStatus(e.currentTarget.value)}
            >
              <For each={["draft", "published", "archived", "resolved"]}>
                {(s) => <option>{s}</option>}
              </For>
            </select>
          </label>
        </div>
        <label>
          Structured content
          <textarea
            class="json-editor"
            spellcheck={false}
            value={value()}
            onInput={(e) => setValue(e.currentTarget.value)}
            required
          />
        </label>
        <label>
          Reason
          <input
            minlength={5}
            required
            value={reason()}
            onInput={(e) => setReason(e.currentTarget.value)}
            placeholder="Explain this change for the audit trail"
          />
        </label>
        {error() ? (
          <p class="error" role="alert">
            {error()}
          </p>
        ) : null}
        <div class="modal-actions">
          <button class="secondary" type="button" onClick={props.close}>
            Cancel
          </button>
          <button class="primary" disabled={busy()}>
            {busy() ? "Saving…" : "Save revision"}
            <Icon name="check" size={16} />
          </button>
        </div>
      </form>
    </Modal>
  );
}
function Operation(props: { data: Row; network: string; chainId: number; close: () => void; saved: () => void }) {
  const [kind, setKind] = createSignal("mint_item"),
    [payload, setPayload] = createSignal<Row>({}),
    [reason, setReason] = createSignal(""),
    [record, setRecord] = createSignal<Row | null>(null),
    [simulation, setSimulation] = createSignal<Row | null>(null),
    [confirmation, setConfirmation] = createSignal(""),
    [busy, setBusy] = createSignal(false),
    [error, setError] = createSignal("");
  onSettled(() => {
    setKind(props.data.kind ?? "mint_item");
    setPayload(props.data.payload ?? {});
    setReason(props.data.reason ?? "");
    if (props.data.id) setRecord(props.data);
  });
  const spec = createMemo(() => operations[kind()] ?? operations.mint_item);
  async function prepare(e: SubmitEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const v: Row = { ...payload() };
      for (const k of ["amount", "token_id", "quantity", "listing_id"])
        if (v[k] !== undefined) v[k] = Number(v[k]);
      for (const k of ["restricted", "enabled"])
        if (v[k] !== undefined) v[k] = String(v[k]) === "true";
      const id = uid();
      await api("operations", {
        id,
        kind: kind(),
        payload: v,
        reason: reason(),
      });
      setRecord(await api("operations/" + id));
      props.saved();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function run(action: string) {
    setBusy(true);
    setError("");
    try {
      const r = await api("operations/" + record()!.id + "/" + action, {});
      if (action === "simulate") setSimulation(r);
      else {
        setRecord(r);
        setSimulation(null);
        setConfirmation("");
        props.saved();
      }
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal
      title={record() ? "Review operation" : "Create operation"}
      close={props.close}
      wide
    >
      <div class="modal-content">
        <div class="info-banner">
          <Icon name="shield" />
          {props.network} · {props.chainId}. Writes use the server operator. Review the
          target, recipient and quantity before signing.
        </div>
        {!record() ? (
          <form onSubmit={prepare}>
            <label>
              Operation
              <select
                value={kind()}
                onChange={(e) => {
                  const k = e.currentTarget.value;
                  setKind(k);
                  setPayload(operations[k].initial ?? {});
                }}
              >
                <For each={Object.entries(operations)}>
                  {([k, v]) => <option value={k}>{v.name}</option>}
                </For>
              </select>
            </label>
            <div class="form-grid">
              <For each={Object.entries(spec().fields)}>
                {([k, label]) => (
                  <label>
                    {label}
                    <input
                      value={String(payload()[k] ?? "")}
                      required
                      onInput={(e) =>
                        setPayload({ ...payload(), [k]: e.currentTarget.value })
                      }
                      placeholder={
                        k === "recipient"
                          ? "0x…"
                          : k === "uri"
                            ? "ipfs://…"
                            : ""
                      }
                    />
                  </label>
                )}
              </For>
            </div>
            <label>
              Reason for this operation
              <textarea
                minlength={8}
                maxlength={1000}
                required
                value={reason()}
                onInput={(e) => setReason(e.currentTarget.value)}
                placeholder="Explain the intended outcome and supporting evidence."
              />
            </label>
            <div class="modal-actions">
              <button class="primary" disabled={busy()}>
                Save intent for review <Icon name="arrow" size={16} />
              </button>
            </div>
          </form>
        ) : (
          <>
            <div class="operation-summary">
              <div>
                <span class="eyebrow">IMMUTABLE INTENT</span>
                <h3>{operations[record()!.kind]?.name ?? record()!.kind}</h3>
                <code>{record()!.id}</code>
              </div>
              <Badge value={record()!.status} />
            </div>
            <p>{record()!.reason}</p>
            <pre>{pretty(record()!.payload)}</pre>
            {record()!.status === "proposed" ? (
              <>
                <button
                  class="secondary"
                  disabled={busy()}
                  onClick={() => void run("simulate")}
                >
                  <Icon name="play" size={15} /> Validate & simulate
                </button>
                {simulation() ? (
                  <div class="execution-review">
                    <span class="badge green">
                      <Icon name="check" size={13} /> Validation passed
                    </span>
                    <pre>{pretty(simulation()!.review)}</pre>
                    <label>
                      Type CONFIRM to execute this exact intent
                      <input
                        value={confirmation()}
                        onInput={(e) => setConfirmation(e.currentTarget.value)}
                        autocomplete="off"
                        placeholder="CONFIRM"
                      />
                    </label>
                    <button
                      class="primary danger"
                      disabled={busy() || confirmation() !== "CONFIRM"}
                      onClick={() => void run("execute")}
                    >
                      Execute operation
                    </button>
                  </div>
                ) : null}
                <button
                  class="text-button"
                  disabled={busy()}
                  onClick={() => void run("cancel")}
                >
                  Cancel proposed operation
                </button>
              </>
            ) : (
              <>
                <pre>{pretty(record()!.result)}</pre>
                <button
                  class="secondary"
                  disabled={busy()}
                  onClick={() => void run("refresh")}
                >
                  <Icon name="refresh" size={16} /> Reconcile chain status
                </button>
              </>
            )}
          </>
        )}
        {error() ? (
          <p class="error" role="alert">
            {error()}
          </p>
        ) : null}
        {busy() ? <p class="muted">Checking the operation…</p> : null}
      </div>
    </Modal>
  );
}
function Invite(props: { close: () => void; saved: () => void }) {
  const [email, setEmail] = createSignal(""),
    [role, setRole] = createSignal("analyst"),
    [reason, setReason] = createSignal(""),
    [error, setError] = createSignal(""),
    [result, setResult] = createSignal<Row | null>(null),
    [status, setStatus] = createSignal("active");
  return (
    <Modal title="Manage administrator" close={props.close}>
      <form
        class="modal-content"
        onSubmit={async (e) => {
          e.preventDefault();
          try {
            setResult(
              await api("identities", {
                email: email(),
                role: role(),
                status: status(),
                reason: reason(),
              }),
            );
            props.saved();
          } catch (e) {
            setError((e as Error).message);
          }
        }}
      >
        {result() ? (
          <>
            <h3>Administrator updated</h3>
            <p>{result()!.message}</p>
            {result()!.access_key ? (
              <code class="secret">{result()!.access_key}</code>
            ) : null}
            <p class="muted">
              Store a newly issued key securely and share it privately with the
              administrator.
            </p>
          </>
        ) : (
          <>
            <label>
              Email
              <input
                type="email"
                required
                value={email()}
                onInput={(e) => setEmail(e.currentTarget.value)}
              />
            </label>
            <label>
              Role
              <select
                value={role()}
                onChange={(e) => setRole(e.currentTarget.value)}
              >
                <For
                  each={[
                    "analyst",
                    "support",
                    "content",
                    "economy",
                    "operations",
                    "owner",
                  ]}
                >
                  {(r) => <option>{r}</option>}
                </For>
              </select>
            </label>
            <label>
              Status
              <select
                value={status()}
                onChange={(e) => setStatus(e.currentTarget.value)}
              >
                <option>active</option>
                <option>revoked</option>
              </select>
            </label>
            <label>
              Reason
              <input
                required
                minlength={5}
                value={reason()}
                onInput={(e) => setReason(e.currentTarget.value)}
              />
            </label>
            <p class="muted">
              Analysts can read. Support handles players and cases. Content
              manages records and artwork. Economy prepares financial writes.
              Operations manages game controls. Owners manage all roles.
            </p>
            {error() ? <p class="error">{error()}</p> : null}
            <button class="primary">
              Save administrator <Icon name="check" />
            </button>
          </>
        )}
      </form>
    </Modal>
  );
}

function parseMintCSV(raw: string): Row[] {
  const cells: string[][] = [];
  let row: string[] = [],
    cell = "",
    quoted = false;
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (c === '"') {
      if (quoted && raw[i + 1] === '"') {
        cell += '"';
        i++;
      } else quoted = !quoted;
    } else if (c === "," && !quoted) {
      row.push(cell);
      cell = "";
    } else if (c === "\n" && !quoted) {
      row.push(cell.replace(/\r$/, ""));
      if (row.some((x) => x.trim())) cells.push(row);
      row = [];
      cell = "";
    } else cell += c;
  }
  if (quoted) throw new Error("A quoted CSV field is not closed.");
  row.push(cell.replace(/\r$/, ""));
  if (row.some((x) => x.trim())) cells.push(row);
  const header = cells.shift()?.map((x) => x.trim().toLowerCase());
  if (!header || header.join(",") !== "recipient,token_id,quantity,uri")
    throw new Error("Use the header recipient,token_id,quantity,uri.");
  if (!cells.length || cells.length > 50)
    throw new Error("Import between 1 and 50 rows.");
  return cells.map((r, i) => {
    const [recipient, token_id, quantity, uri] = r.map((x) => x.trim());
    const id = Number(token_id),
      qty = Number(quantity);
    if (
      r.length !== 4 ||
      token_id === "" ||
      !/^0x[0-9a-fA-F]{40}$/.test(recipient) ||
      /^0x0{40}$/.test(recipient) ||
      ![0, 1, 2, 3, 4, 5, 11, 12, 13].includes(id) ||
      !Number.isInteger(qty) ||
      qty < 1 ||
      qty > 10000 ||
      !/^https:\/\/|^ipfs:\/\//.test(uri) ||
      uri.length > 2048
    )
      throw new Error(
        "Row " +
          (i + 2) +
          ": check recipient, registered token ID, quantity and metadata URI.",
      );
    return { id: uid(), recipient, token_id: id, quantity: qty, uri };
  });
}
function BatchMint(props: { close: () => void; saved: () => void }) {
  const [csv, setCSV] = createSignal("recipient,token_id,quantity,uri\n"),
    [rows, setRows] = createSignal<Row[]>([]),
    [reason, setReason] = createSignal(""),
    [error, setError] = createSignal(""),
    [busy, setBusy] = createSignal(false),
    [done, setDone] = createSignal(0);
  async function prepare(e: SubmitEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const list = rows(),
      why = reason();
    try {
      for (let i = done(); i < list.length; i++) {
        const r = list[i];
        await api("operations", {
          id: r.id,
          kind: "mint_item",
          reason: why,
          payload: {
            recipient: r.recipient,
            token_id: r.token_id,
            quantity: r.quantity,
            uri: r.uri,
          },
        });
        setDone(i + 1);
      }
      props.saved();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal
      title="Import mint intents"
      close={() => {
        if (!busy()) props.close();
      }}
      wide
    >
      <div class="modal-content">
        <div class="info-banner">
          <Icon name="shield" />
          Validate up to 50 recipients. Import saves separate immutable intents.
          Each mint still requires simulation and confirmation in Minting
          studio.
        </div>
        <label class="secondary file-button">
          Choose CSV file
          <input
            type="file"
            accept=".csv,text/csv"
            disabled={busy()}
            onChange={async (e) => {
              const file = e.currentTarget.files?.[0];
              if (file) {
                if (file.size > 100000) {
                  setError("CSV must be under 100 KB.");
                  return;
                }
                setCSV(await file.text());
                setRows([]);
                setDone(0);
              }
            }}
          />
        </label>
        <label>
          CSV content
          <textarea
            class="json-editor"
            value={csv()}
            disabled={busy()}
            onInput={(e) => {
              setCSV(e.currentTarget.value);
              setRows([]);
              setDone(0);
            }}
          />
        </label>
        <button
          class="secondary"
          disabled={busy()}
          onClick={() => {
            try {
              setRows(parseMintCSV(csv()));
              setDone(0);
              setError("");
            } catch (e) {
              setError((e as Error).message);
            }
          }}
        >
          Validate rows <Icon name="check" size={15} />
        </button>
        {rows().length ? (
          <>
            <Records rows={rows()} inspect={() => {}} />
            <form onSubmit={prepare}>
              <label>
                Reason for this batch
                <input
                  required
                  minlength={8}
                  maxlength={1000}
                  disabled={busy() || done() > 0}
                  value={reason()}
                  onInput={(e) => setReason(e.currentTarget.value)}
                />
              </label>
              <button
                class="primary"
                disabled={busy() || done() === rows().length}
              >
                {busy()
                  ? "Saving intents…"
                  : done()
                    ? "Resume import"
                    : "Save " + rows().length + " mint intents"}
              </button>
              <p class="muted">
                {done()} / {rows().length} intents saved. No mint transactions
                have been sent.
              </p>
            </form>
          </>
        ) : null}
        {error() ? (
          <p class="error" role="alert">
            {error()}
          </p>
        ) : null}
      </div>
    </Modal>
  );
}
