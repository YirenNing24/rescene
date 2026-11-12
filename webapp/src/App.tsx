import { createSignal, onSettled } from 'solid-js';
import release from '../public/release.json';
const releaseSize: string = (release.bytes / 1_000_000).toFixed(1) + ' MB';
import { api, ApiError, cardImage, members, number, requestID } from './api';
import { Icon } from './Icons';
import { Avatar, CardArtwork, Empty, SectionTitle } from './ui';
import { Auth } from './Auth';
import { Marketplace, Collection } from './Collection';
import { Events } from './Events';
import { Coop } from './Coop';
import { Rewards, Songs, Records } from './Progress';
import { Profile, Community } from './Community';
import type { User, Progress, Inventory, Media, StarBalance, Social, Operation, Wallet } from './types';
export type Page = 'Lobby'|'Collection'|'Marketplace'|'Rewards'|'Events'|'Duet'|'Songs'|'Rankings'|'Community'|'Profile'|'Download';
export interface Shared {
  user: User | null; progress: Progress | null; inventory: Inventory | null; media: Media | null; balance: StarBalance | null; social: Social | null;
  refresh: () => Promise<void>; notify: (message: string) => void; navigate: (page: Page) => void; signIn: () => void; logout: () => Promise<void>;
}
const nav: {label: Page; icon: string}[]=[{label:'Lobby',icon:'home'},{label:'Collection',icon:'card'},{label:'Marketplace',icon:'bag'},{label:'Rewards',icon:'gift'},{label:'Events',icon:'flag'},{label:'Duet',icon:'people'},{label:'Songs',icon:'music'},{label:'Rankings',icon:'trophy'},{label:'Community',icon:'people'}];
const pages: Page[]=[...nav.map(n=>n.label),'Profile','Download'];
export default function App() {
  const [page,setPage]=createSignal<Page>('Lobby'); const [user,setUser]=createSignal<User|null>(null);const [ready,setReady]=createSignal(false);
  const [progress,setProgress]=createSignal<Progress|null>(null);const [inventory,setInventory]=createSignal<Inventory|null>(null);const [media,setMedia]=createSignal<Media|null>(null);const [balance,setBalance]=createSignal<StarBalance|null>(null);const [social,setSocial]=createSignal<Social|null>(null);
  const [auth,setAuth]=createSignal(false); const [menu,setMenu]=createSignal(false); const [toast,setToast]=createSignal('');const [syncError,setSyncError]=createSignal('');const [refreshing,setRefreshing]=createSignal(false);
  let toastTimer: ReturnType<typeof setTimeout> | undefined;let polling=false;let syncing: Promise<void> | undefined; let device='';let accountEpoch=0;
  const notify=(message:string):void=>{setToast(message);clearTimeout(toastTimer);toastTimer=setTimeout(()=>setToast(''),6500);};
  function navigate(next:Page):void {setPage(next);setMenu(false);history.replaceState(null,'','#'+next.toLowerCase());document.querySelector('main')?.scrollTo({top:0});}
  function clear():void {accountEpoch++;syncing=undefined;setRefreshing(false);setSyncError('');setUser(null);setProgress(null);setInventory(null);setMedia(null);setBalance(null);setSocial(null);}
  async function refresh():Promise<void> {
    if(syncing)return syncing;
    const epoch=accountEpoch;
    const commit=(apply:()=>void):void=>{if(epoch===accountEpoch)apply();};
    const work=(async()=>{
      setRefreshing(true);
      const results=await Promise.allSettled([
        api<{progression:Progress}>('/progression').then(r=>commit(()=>setProgress(r.progression))),
        api<Inventory>('/inventory').then(r=>commit(()=>{setInventory(r);if(r.progression)setProgress(r.progression);})),
        api<{media:Media}>('/profile/media').then(r=>commit(()=>setMedia(r.media))),
        api<{starlight:StarBalance}>('/starlight').then(r=>commit(()=>setBalance(r.starlight))),
        api<{social:Social}>('/social').then(r=>commit(()=>setSocial(r.social))),
        api<{wallet:Wallet}>('/wallet').then(r=>commit(()=>setUser(previous=>previous?{...previous,wallet:r.wallet}:null)))
      ]);
      const failures=results.filter(r=>r.status==='rejected');
      commit(()=>{setSyncError(failures.length ? 'Some account data could not refresh. Your previous data is still shown.' : '');setRefreshing(false);});
    })();syncing=work;try{await work;}finally{if(syncing===work)syncing=undefined;}
  }
  async function logout():Promise<void>{try{await api('/logout',{});clear();navigate('Lobby');notify('You are signed out.');}catch(err){notify(err instanceof Error?err.message:'Could not sign out.');}}
  async function presence(online=true):Promise<void>{if(!user()||!device)return;await api('/social/presence',{device_id:device,online,activity:'menu'}).catch(()=>undefined);}
  onSettled(()=>{
    device=requestID();const selected=location.hash.slice(1);const match=pages.find(p=>p.toLowerCase()===selected);if(match)setPage(match);
    const expired=():void=>{if(user()){clear();notify('Please sign in again to continue.');}};window.addEventListener('session-expired',expired);
    void (async()=>{try{const r=await api<{user:User}>('/session');setUser(r.user);await refresh();await presence();}catch(err){if(!(err instanceof ApiError&&err.status===401))setSyncError('Could not reach your account. Refresh to reconnect.');}finally{setReady(true);}})();
    const timer=setInterval(()=>{if(!user()||document.hidden||polling)return;polling=true;void(async()=>{
      try{const old=inventory()?.operation;const epoch=accountEpoch; if(old&&!['confirmed','failed'].includes(old.status)){
        const next=await api<Inventory>('/inventory');if(epoch!==accountEpoch)return;setInventory(next);if(next.progression)setProgress(next.progression);
        if(next.operation&&['confirmed','failed'].includes(next.operation.status)){notify(operationMessage(next.operation));await refresh();}
      }}catch{}finally{polling=false;}
    })();},5000);
    const socialTimer=setInterval(()=>{const epoch=accountEpoch;if(user()&&!document.hidden)void api<{social:Social}>('/social').then(r=>{if(epoch===accountEpoch)setSocial(r.social);}).catch(()=>undefined);},20000);
    const presenceTimer=setInterval(()=>{if(!document.hidden)void presence();},30000);
    const progressTimer=setInterval(()=>{const epoch=accountEpoch;if(user()&&!document.hidden)void api<{progression:Progress}>('/progression').then(r=>{if(epoch===accountEpoch)setProgress(r.progression);}).catch(()=>undefined);},60000);
    const recover=():void=>{if(!document.hidden&&user()){void presence();void refresh();}};document.addEventListener('visibilitychange',recover);
    return()=>{clearInterval(timer);clearInterval(socialTimer);clearInterval(presenceTimer);clearInterval(progressTimer);clearTimeout(toastTimer);window.removeEventListener('session-expired',expired);document.removeEventListener('visibilitychange',recover);};
  });
  const shared=():Shared=>({user:user(),progress:progress(),inventory:inventory(),media:media(),balance:balance(),social:social(),refresh,notify,navigate,signIn:()=>setAuth(true),logout});
  const pending=():boolean=>!!inventory()?.operation&&!['confirmed','failed'].includes(inventory()!.operation!.status);
  const needsAccount=():boolean=>!['Lobby','Songs','Download'].includes(page())&&!user();
  return <div class="app"><div class="world-bg"/><a class="skip-link" href="#main">Skip to content</a><aside class={menu()?'sidebar open':'sidebar'}><a class="wordmark" href="#lobby" onClick={e=>{e.preventDefault();navigate('Lobby');}}><span>RESCÉNE</span><i>RHYTHM</i></a><p class="nav-heading">YOUR BACKSTAGE</p><nav aria-label="Game navigation">{nav.map(item=><button aria-label={item.label} class={page()===item.label?'active':''} onClick={()=>navigate(item.label)}><Icon name={item.icon}/><span>{item.label}</span>{item.label==='Community'&&!!social()?.unread&&<b class="count">{social()!.unread}</b>}{item.label==='Rewards'&&user()&&!progress()?.daily_login.claimed_today&&<i class="nav-dot"/>}</button>)}</nav><div class="sidebar-bottom"><a class="button primary small" href="/download"><Icon name="down" size={17}/>Get Android APK</a><button class="quiet" onClick={()=>navigate('Download')}>Version & installation <Icon name="arrow" size={14}/></button><a class="fansite-link" href="https://remineph.online">← Back to REMINE</a><span class="micro">YOUR MUSIC. YOUR MOMENT.</span></div></aside>{menu()&&<button class="menu-scrim" aria-label="Close navigation" onClick={()=>setMenu(false)}/>}
    <div class="workspace"><header class="hud"><button class="icon-button mobile-menu" aria-label="Open navigation" onClick={()=>setMenu(true)}><Icon name="menu"/></button><button class="player-button" onClick={()=>user()?navigate('Profile'):setAuth(true)}><Avatar name={user()?.username ?? 'R'} photo={media()?.avatar}/><span><strong>{user()?.username ?? 'RE:PLAYER'}</strong><small>{user()?'LV. '+String(progress()?.level ?? 1).padStart(2,'0')+' / YOUR BACKSTAGE':'YOUR NEXT SCENE STARTS HERE'}</small></span></button><span class="hud-center">RESCÉNE / RHYTHM</span><div class="currencies"><div class="currency"><Icon name="heart"/><span><small>ENERGY</small><b>{progress()?`${progress()!.energy.current} / ${progress()!.energy.max}`:'—'}</b></span></div><button class="currency" onClick={()=>navigate('Profile')}><Icon name="star"/><span><small>STARLIGHT</small><b>{number(balance()?.balance)}</b></span></button><button class="icon-button" aria-label="Friends and messages" onClick={()=>navigate('Community')}><Icon name="message"/>{!!social()?.unread&&<i class="nav-dot"/>}</button><button class="icon-button" aria-label="Account settings" onClick={()=>user()?navigate('Profile'):setAuth(true)}><Icon name="settings"/></button></div></header>
    <main id="main" tabindex="-1">{syncError()&&<div class="sync-banner" role="status">{syncError()}<button disabled={refreshing()} onClick={()=>user()?void refresh():location.reload()}>{refreshing()?'Refreshing…':'Retry'}</button></div>}{pending()&&<div class="operation-banner"><span class="spinner"/>Your {inventory()!.operation!.kind==='buy'?'purchase':'card or item action'} is processing. You can safely leave this page.<button onClick={()=>navigate('Collection')}>View inventory →</button></div>}
    {!ready()?<div class="loading-screen"><span class="spinner"/><p>Opening your backstage…</p></div>:needsAccount()?<div class="page"><SectionTitle eyebrow="YOUR BACKSTAGE" title={page()}/><Empty icon="user" title="Your scene is waiting." text="Sign in with your game account to see your cards, rewards, and friends."><button class="button primary" onClick={()=>setAuth(true)}>Sign in / Create account<Icon name="arrow"/></button></Empty></div>:<>
    {page()==='Lobby'&&<Lobby shared={shared()}/>}{page()==='Marketplace'&&<Marketplace shared={shared()}/>}{page()==='Collection'&&<Collection shared={shared()}/>}{page()==='Rewards'&&<Rewards shared={shared()}/>}{page()==='Events'&&<Events shared={shared()}/>}{page()==='Duet'&&<Coop shared={shared()}/>} {page()==='Songs'&&<Songs shared={shared()}/>}{page()==='Rankings'&&<Records shared={shared()}/>}{page()==='Profile'&&<Profile shared={shared()}/>}{page()==='Community'&&<Community shared={shared()}/>}{page()==='Download'&&<Download/>}</>}
    </main><footer class="app-footer"><span>RESCÉNE RHYTHM / YOUR STAGE AWAITS</span><span>WITH · REMINE</span></footer></div>{toast()&&<div class="toast" role="status"><Icon name="spark" size={18}/><span>{toast()}</span><button class="icon-button" aria-label="Dismiss notification" onClick={()=>setToast('')}><Icon name="close" size={16}/></button></div>}{auth()&&<Auth onClose={()=>setAuth(false)} onLogin={async u=>{setUser(u);await refresh();await presence();notify('Welcome back, '+u.username+'.');}}/>}</div>;
}
function operationMessage(operation:Operation):string {if(operation.status==='failed')return operation.message ?? 'Your action could not complete.';if(operation.kind==='buy')return 'Your purchase is ready in Inventory.';if(operation.energy_restored)return `Energy restored: +${operation.energy_restored}.`;if(operation.level_upgraded===false)return 'Refinement complete. Your XP is preserved; the level attempt did not succeed.';return 'Your card action is confirmed.';}
function Lobby(props:{shared:Shared}) {
  return <div class="lobby"><div class="lobby-copy"><p class="eyebrow"><span class="live-dot"/>YOUR BACKSTAGE, EVERYWHERE</p><h1>RESCÉNE<i>Rhythm</i></h1><p class="lobby-tagline">Your stage. Your scene.</p><span class="ornament">✧</span></div><div class="lobby-left"><button class="feature-tile" onClick={()=>props.shared.navigate('Events')}><span class="eyebrow">THE PULSE EVENT</span><h3>With you,<br/><i>in every beat.</i></h3><span>Explore the event <Icon name="arrow" size={16}/></span></button><button class="lobby-small" onClick={()=>props.shared.user?props.shared.navigate('Rewards'):props.shared.signIn()}><Icon name="gift" size={23}/><span><strong>DAILY GIFTS</strong><small>{props.shared.progress?.daily_login.claimed_today?'A new gift awaits tomorrow':'A little something, every day'}</small></span><Icon name="arrow" size={16}/></button><button class="lobby-small" onClick={()=>props.shared.user?props.shared.navigate('Collection'):props.shared.signIn()}><Icon name="card" size={23}/><span><strong>YOUR PULSE DECK</strong><small>Five members. One perfect harmony.</small></span><Icon name="arrow" size={16}/></button></div><aside class="friend-rail"><span class="micro">ONLINE</span>{(props.shared.social?.online_friends ?? []).slice(0,5).map(friend=><button title={friend.username} onClick={()=>props.shared.navigate('Community')}><Avatar name={friend.username} photo={friend.avatar} online/></button>)}{!props.shared.social?.online_friends.length&&<button class="friend-empty" aria-label="Find friends" onClick={()=>props.shared.user?props.shared.navigate('Community'):props.shared.signIn()}><Icon name="people" size={24}/><small>Find your<br/>REMINE</small></button>}</aside><div class="lobby-bottom"><div><p class="eyebrow">01 / THE FIRST SCENE</p><h2>In every beat,<br/><i>a little more you.</i></h2><p>Collect, connect, and get ready for your next stage.</p></div><div class="lobby-actions">{!props.shared.user&&<button class="button glass" onClick={props.shared.signIn}>Enter your backstage<Icon name="user"/></button>}<a class="button primary download-hero" href="/download"><span><small>PLAY ON ANDROID</small>Download APK</span><Icon name="down" size={26}/></a><button class="quiet" onClick={()=>props.shared.navigate('Download')}>v{release.version} · {releaseSize} · Installation guide<Icon name="arrow" size={14}/></button></div></div></div>;
}
function Download() {
  return <div class="page download-page"><SectionTitle eyebrow="THE STAGE IS YOURS" title="Take the rhythm with you." text="Play RESCENE Rhythm on Android. Your web account, collection, and progress come with you."/><div class="download-layout"><div class="download-art"><CardArtwork src="/images/card-woni.webp" name="Woni PULSE Limited Edition card"/><CardArtwork src="/images/card-minami.webp" name="Minami PULSE Limited Edition card"/><CardArtwork src="/images/card-zena.webp" name="Zena PULSE Limited Edition card"/></div><div class="panel stack"><span class="badge">ANDROID · v{release.version}</span><h2>Your next scene<br/><i>starts here.</i></h2><p class="muted">Five lanes. Curving notes. Your favorite RESCENE songs. Download the standalone game and sign in with the same account.</p><a class="button primary" href="/download"><Icon name="down"/>Download Android APK <span class="button-end">{releaseSize}</span></a><ol class="install-steps"><li><b>Download the APK</b><span>Open this page on your Android device and save the file.</span></li><li><b>Allow this installation</b><span>If Android asks, allow your browser to install apps from this source.</span></li><li><b>Install and sign in</b><span>Open RESCENE Rhythm and use your existing account.</span></li></ol><p class="micro">THE WEB COMPANION HAS NO SONG PLAYBACK OR GAMEPLAY.</p><details><summary>File verification</summary><p class="muted">{release.file} · {release.bytes.toLocaleString()} bytes</p><code class="break">SHA-256: {release.sha256}</code></details></div></div></div>;
}
