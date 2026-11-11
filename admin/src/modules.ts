export type Module = {
  id: string;
  name: string;
  group: string;
  icon: string;
  path: string;
  description: string;
  document?: string;
  note?: string;
};
export const modules: Module[] = [
  {
    id: "overview",
    name: "Overview",
    group: "Workspace",
    icon: "grid",
    path: "overview",
    description:
      "Your game, at a glance. Real accounts, activity and operations.",
  },
  {
    id: "analytics",
    name: "Analytics",
    group: "Workspace",
    icon: "chart",
    path: "data/analytics",
    description: "Observed player activity, API outcomes and daily usage.",
    note: "Telemetry starts with this deployment. Historical retention, acquisition attribution and crash reporting are not available yet.",
  },
  {
    id: "players",
    name: "Players",
    group: "Workspace",
    icon: "users",
    path: "players",
    description:
      "Find a player. Understand their journey. Help them move forward.",
  },
  {
    id: "social",
    name: "Friends & profiles",
    group: "Workspace",
    icon: "heart",
    path: "data/social",
    description:
      "Following, mutual friends, blocks and player profile moderation.",
    note: "Mutual follows create a friendship. Open any player to inspect their profile, gallery and relationships.",
  },
  {
    id: "support",
    name: "Support inbox",
    group: "Workspace",
    icon: "inbox",
    path: "documents/support",
    document: "support",
    description: "Track player cases, investigation notes and resolutions.",
  },
  {
    id: "runs",
    name: "Runs & validation",
    group: "Game",
    icon: "play",
    path: "data/runs",
    description: "Inspect current run tickets, reservations and expiration.",
  },
  {
    id: "songs",
    name: "Songs & charts",
    group: "Game",
    icon: "music",
    path: "data/charts",
    description:
      "The authoritative embedded chart catalog and revision boundaries.",
    note: "Chart changes require a compatible API and game release. Stage reviewed imports in Releases.",
  },
  {
    id: "leaderboards",
    name: "Leaderboards",
    group: "Game",
    icon: "trophy",
    path: "data/scores",
    description: "Verified personal bests, rankings and moderation.",
  },
  {
    id: "missions",
    name: "Missions & gifts",
    group: "Game",
    icon: "target",
    path: "documents/missions",
    document: "missions",
    description: "Plan mission definitions, eligibility and reward policies.",
    note: "These versioned proposals need a compatible game release before they change player rewards.",
  },
  {
    id: "calendars",
    name: "Daily calendars",
    group: "Game",
    icon: "calendar",
    path: "documents/calendars",
    document: "calendars",
    description: "Prepare reward calendars and claim migration policies.",
    note: "Calendar proposals do not alter the compiled reward schedule.",
  },
  {
    id: "events",
    name: "Events",
    group: "Game",
    icon: "spark",
    path: "documents/events",
    document: "events",
    description: "Plan scheduled events and eligibility windows.",
    note: "Event delivery and reward multipliers require client/API release integration.",
  },
  {
    id: "store",
    name: "Store catalog",
    group: "Economy",
    icon: "bag",
    path: "catalog",
    description: "Inspect live products, prices and availability.",
    note: "Router prices are immutable. Merchandising changes can be drafted in Releases.",
  },
  {
    id: "items",
    name: "Items & inventory",
    group: "Economy",
    icon: "box",
    path: "data/items",
    description:
      "Registered item IDs, materials and intended use. Inspect owned inventory from a player profile.",
  },
  {
    id: "minting",
    name: "Minting studio",
    group: "Economy",
    icon: "plus",
    path: "data/minting",
    description:
      "Prepare, simulate and track item issuance. Every intent has a stable operation ID.",
  },
  {
    id: "cards",
    name: "Card registry",
    group: "Economy",
    icon: "cards",
    path: "data/cards",
    description:
      "Card purchase and upgrade operations linked to their players.",
    note: "Unique PULSE ownership becomes available after its router is deployed. Existing First Scene collectibles are cosmetic.",
  },
  {
    id: "refinement",
    name: "Refinement & skills",
    group: "Economy",
    icon: "spark",
    path: "data/refinement",
    description: "Inspect card upgrade attempts and permanent trait rules.",
  },
  {
    id: "decks",
    name: "Album decks",
    group: "Economy",
    icon: "layers",
    path: "data/decks",
    description: "Run-bound five-member deck snapshots and reservations.",
  },
  {
    id: "transactions",
    name: "Transactions",
    group: "Economy",
    icon: "arrows",
    path: "data/transactions",
    description: "Orders, payouts and leaderboard publications in one place.",
  },
  {
    id: "recovery",
    name: "Recovery queue",
    group: "Economy",
    icon: "refresh",
    path: "data/recovery",
    description: "Investigate failures and safely wake original durable jobs.",
  },
  {
    id: "treasury",
    name: "Treasury & gas",
    group: "Blockchain",
    icon: "wallet",
    path: "chain",
    description: "Live treasury balance, token supply and native gas.",
  },
  {
    id: "wallets",
    name: "Player wallets",
    group: "Blockchain",
    icon: "wallet",
    path: "data/wallets",
    description: "Provisioning, retries and linked Engine wallets.",
  },
  {
    id: "contracts",
    name: "Contracts",
    group: "Blockchain",
    icon: "code",
    path: "contracts",
    description:
      "The deployed registry, network and supported operator actions.",
  },
  {
    id: "launch",
    name: "PULSE launch",
    group: "Blockchain",
    icon: "rocket",
    path: "data/launch",
    description: "Deployment, material stock and supply policy readiness.",
  },
  {
    id: "settings",
    name: "Game controls",
    group: "Administration",
    icon: "sliders",
    path: "documents/settings",
    description:
      "Live maintenance, purchases, run admission, uploads and social controls.",
  },
  {
    id: "announcements",
    name: "Announcements",
    group: "Administration",
    icon: "megaphone",
    path: "documents/announcements",
    document: "announcements",
    description: "Prepare localized notices, targeting and expiry.",
    note: "In-game delivery requires the announcement feed in a compatible client release.",
  },
  {
    id: "media",
    name: "Media library",
    group: "Administration",
    icon: "image",
    path: "documents/assets",
    description:
      "Private artwork assets with normalized images and content hashes.",
  },
  {
    id: "moderation",
    name: "Moderation",
    group: "Administration",
    icon: "shield",
    path: "documents/reports",
    document: "reports",
    description: "Investigate profile, photo, social and score reports.",
  },
  {
    id: "team",
    name: "Team & access",
    group: "Administration",
    icon: "key",
    path: "identities",
    description:
      "Invite administrators and assign scoped roles. Authenticator verification is mandatory.",
  },
  {
    id: "audit",
    name: "Audit log",
    group: "Administration",
    icon: "list",
    path: "data/audit",
    description: "Recorded administrator writes, actors, roles and outcomes.",
  },
  {
    id: "monitoring",
    name: "System health",
    group: "Administration",
    icon: "pulse",
    path: "data/health",
    description: "Database health and enabled backend integrations.",
  },
  {
    id: "releases",
    name: "Releases & backups",
    group: "Administration",
    icon: "git",
    path: "documents/releases",
    document: "releases",
    description:
      "Track API, game and contract changes with a reviewable rollout plan.",
    note: "Publishing records the release plan. It does not deploy builds or create database backups automatically.",
  },
  {
    id: "history",
    name: "Version history",
    group: "Administration",
    icon: "clock",
    path: "data/history",
    description:
      "Inspect prior document values before restoring a reviewed revision.",
  },
];
export const operations: Record<
  string,
  {
    name: string;
    fields: Record<string, string>;
    initial?: Record<string, unknown>;
  }
> = {
  mint_item: {
    name: "Mint registered items",
    fields: {
      recipient: "Recipient wallet",
      token_id: "Token ID (0–5, 11–13)",
      quantity: "Quantity (1–10,000)",
      uri: "Reviewed metadata URI",
    },
  },
  transfer_starl: {
    name: "Transfer STARL",
    fields: { recipient: "Recipient wallet", amount: "Whole STARL amount" },
  },
  compensate_starl: {
    name: "Compensate STARL",
    fields: { recipient: "Recipient wallet", amount: "Whole STARL amount" },
  },
  approve_allowance: {
    name: "Approve bounded allowance",
    fields: {
      recipient: "Configured router address",
      amount: "Whole STARL amount",
    },
  },
  suspend: { name: "Suspend account", fields: { player_id: "Player ID" } },
  restore: { name: "Restore account", fields: { player_id: "Player ID" } },
  revoke_sessions: {
    name: "Revoke all player sessions",
    fields: { player_id: "Player ID" },
  },
  grant_xp: {
    name: "Grant support XP",
    fields: { player_id: "Player ID", amount: "Amount (1–100,000)" },
  },
  grant_energy: {
    name: "Grant energy",
    fields: { player_id: "Player ID", amount: "Amount (1–15)" },
  },
  restrict_uploads: {
    name: "Restrict photo uploads",
    fields: { player_id: "Player ID", restricted: "Restricted (true/false)" },
    initial: { restricted: true },
  },
  restrict_social: {
    name: "Restrict social interactions",
    fields: { player_id: "Player ID", restricted: "Restricted (true/false)" },
    initial: { restricted: true },
  },
  quarantine_photo: {
    name: "Quarantine photo",
    fields: { player_id: "Player ID", photo_id: "Photo ID" },
  },
  restore_photo: {
    name: "Restore photo",
    fields: { player_id: "Player ID", photo_id: "Photo ID" },
  },
  quarantine_score: {
    name: "Quarantine off-chain record",
    fields: { score_id: "Personal best key" },
  },
  restore_score: {
    name: "Restore off-chain record",
    fields: { score_id: "Personal best key" },
  },
  retry_job: {
    name: "Wake original durable job",
    fields: {
      job_type: "Job type (shop/payout/score/wallet)",
      job_id: "Original job key",
    },
  },
  leaderboard_pause: { name: "Pause leaderboard publication", fields: {} },
  leaderboard_unpause: { name: "Resume leaderboard publication", fields: {} },
  board_enable: {
    name: "Set board availability",
    fields: { board_id: "Board ID (bytes32)", enabled: "Enabled (true/false)" },
  },
  listing_create: {
    name: "Create stock listing",
    fields: {
      token_id: "Registered stock token ID",
      quantity: "Stock quantity",
      price: "Fixed whole STARL price",
      starts_at: "Start (Unix seconds)",
      ends_at: "End (Unix seconds)",
    },
  },
  listing_update: {
    name: "Update stock listing",
    fields: {
      listing_id: "Listing ID",
      token_id: "Registered stock token ID",
      quantity: "Stock quantity",
      price: "Fixed whole STARL price",
      starts_at: "Start (Unix seconds)",
      ends_at: "End (Unix seconds)",
    },
  },
  listing_cancel: {
    name: "Cancel marketplace listing",
    fields: { listing_id: "Listing ID" },
  },
  pulse_sales: {
    name: "PULSE initial sales",
    fields: { enabled: "Sales enabled (true / false)" },
    initial: { enabled: false },
  },
  generate_card: {
    name: "Generate individual PULSE card",
    fields: { recipient: "Recipient wallet", member: "Member index: Woni 0, Liv 1, Minami 2, May 3, Zena 4", rarity: "Rarity: Common 0 through LE 5" },
    initial: { member: 0, rarity: 5 },
  },
};
export const templates: Record<string, unknown> = {
  support: {
    player_id: "",
    category: "missing_reward",
    priority: "normal",
    summary: "",
    resolution: "",
  },
  notes: { player_id: "", note: "" },
  reports: {
    player_id: "",
    category: "photo",
    photo_id: "",
    evidence: "",
    resolution: "",
  },
  missions: {
    key: "",
    objective: "clears",
    target: 3,
    reward: { xp: 100 },
    requires_release: true,
  },
  calendars: {
    name: "",
    days: [],
    claim_migration: "preserve_existing",
    requires_release: true,
  },
  announcements: {
    title: "",
    body: "",
    locale: "en",
    starts_at: "",
    ends_at: "",
    requires_release: true,
  },
  events: {
    starts_at: "",
    ends_at: "",
    eligibility: {},
    reward_policy: {},
    requires_release: true,
  },
  releases: {
    kind: "api",
    version: "",
    changes: [],
    validation: [],
    rollout: "",
    rollback: "",
    backup_artifact: "",
    status: "planned",
  },
};
