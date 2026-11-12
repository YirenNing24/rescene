export interface Wallet { address?: string; status: string; custody: string }
export interface User { id: string; username: string; created_at: string; wallet?: Wallet }
export interface Photo { id: string; url: string }
export interface Media { avatar: Photo | null; gallery: Photo[]; gallery_limit: number }
export interface Mission { id: string; name: string; description: string; scope: string; target: number; progress: number; xp: number; starlight: number; claimed: boolean }
export interface Cosmetic { id: string; name: string; kind: string; requirement: string; unlocked: boolean; equipped: boolean; color: string }
export interface Reward { day: number; xp: number; starlight: number }
export interface Progress { server_time?: string; events?: TimedEvent[]; day: string; level: number; xp: number; level_xp: number; level_cost: number; starlight: number; clears: number; best_accuracy: number; max_combo: number; full_combos: number; missions: Mission[]; unlocks: Cosmetic[]; energy: {current: number; max: number; next_recovery_in_seconds: number}; daily_login: {date: string; completed: number; next_day: number; claimed_today: boolean; rewards: Reward[]} }
export interface Product { id: string; name: string; category: string; set_id?: string; series?: string; art_slug?: string; member?: string; price: number; currency: string; available: boolean; stock: number; max_quantity: number; training_xp?: number; initial_allocation?: number }
export interface Item { id: string; name: string; category: string; set_id?: string; series?: string; art_slug?: string; member?: string; member_index?: number; quantity: number; template_id?: string; level?: number; stars?: number; locked?: boolean; equipped?: boolean; in_use?: boolean; listed?: boolean; rarity?: string; skill?: string; skill_description?: string; training_xp?: number; level_cost?: number; success_chance_bp?: number; star_progress?: number; star_cost?: number; stats?: {perfect_score_bp: number; recovery_ppm: number}; training_xp_added?: number }
export interface Operation { key: string; request_id: string; status: string; kind: string; item_id?: string; message?: string; transaction_hash?: string; level_upgraded?: boolean; level_after?: number; energy_restored?: number }
export interface Inventory { enabled: boolean; items: Item[]; operation: Operation | null; decks?: Record<string, string[]>; progression?: Progress }
export interface StarBalance { status: string; balance?: string; pending?: string; wallet_address?: string; chain_id?: number; contract_address?: string }
export interface RecordScore { song_id: string; title: string; difficulty: string; score: number; max_combo: number; accuracy: number; rank: string; achieved_at: number }
export interface BoardEntry extends RecordScore { user_id: string; username: string; position: number }
export interface Player { id: string; username: string; avatar: Photo | null; following: boolean; follows_you: boolean; friend: boolean; online: boolean; blocked_by_me: boolean; can_chat: boolean; activity: string }
export interface Conversation { peer: Player; last_text: string; unread: number; last_at: number; seq: number }
export interface Social { counts: {followers: number; following: number; friends: number}; online_friends: Player[]; conversations: Conversation[]; unread: number }
export interface Message { id: string; sender_id: string; text: string; seq: number; sent_at: number }
export interface Challenge { id: string; sender: string; recipient: string; sender_name: string; recipient_name: string; title: string; song_id: string; difficulty: string; status: string; score_a: number; score_b: number; expires_at: number; winner?: string }
export interface PublicProfile { id: string; username: string; created_at: string; media: Media; progression: Pick<Progress,'xp'|'level'|'level_xp'|'level_cost'|'clears'|'best_accuracy'|'max_combo'|'full_combos'> & {title_name: string}; records: RecordScore[] }
export interface CardAction { kind: 'equip'|'lock'|'refine'|'star'; card_id: string; set_id?: string; member_index?: number; locked?: boolean; item_id?: string; donors?: string[]; request_id?: string; quote_hash?: string; acknowledge_warning?: boolean }
export interface Quote { hash: string; warnings: string[]; success_chance_bp: number; level_before: number; level_after: number; xp_added: number; stars_before: number; stars_after: number; star_progress_after: number; donors_wasted: number }
export interface EventMission { id: string; name: string; description: string; target: number; progress: number; xp: number; starlight: number; shards: number; claimed: boolean; claimable: boolean }
export interface TimedEvent { id: string; name: string; subtitle: string; set_id: string; status: 'upcoming'|'active'|'claiming'|'ended'; starts_at: string; ends_at: string; claim_ends_at: string; featured_song_id: string; featured_title: string; rotation_at: string; missions: EventMission[]; rules: string }

export interface MasteryMilestone {id:string;name:string;description:string;complete:boolean;claimed:boolean;xp:number;starlight:number;shards:number}
export interface SongMastery {song_id:string;milestones:MasteryMilestone[];completed:number;claimed:number;total:number;best_accuracy:number;full_combo:boolean}
