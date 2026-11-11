import { createSignal } from 'solid-js';
import { api } from './api';
import { LegalPolicy, policies, type PolicyKind } from './Legal';
import { Icon } from './Icons';
import { Modal, Tabs } from './ui';
import type { User } from './types';
export function Auth(props: {onClose: () => void; onLogin: (user: User) => Promise<void>}) {
  const [mode,setMode]=createSignal('Sign in');
  const [username,setUsername]=createSignal(''); const [password,setPassword]=createSignal(''); const [recovery,setRecovery]=createSignal('');
  const [accepted,setAccepted]=createSignal(false);
  const [legal,setLegal]=createSignal<PolicyKind | null>(null);
  const [busy,setBusy]=createSignal(false); const [error,setError]=createSignal('');
  async function submit(e: SubmitEvent): Promise<void> {
    e.preventDefault();setError('');
    if(mode()==='Create account' && !accepted()) {setError('Please agree to the Terms & Conditions and acknowledge the Privacy Policy.');return;}
    setBusy(true);
    try {
      if(mode()==='Recover') {
        await api('/auth/recover',{username:username(),recovery_code:recovery(),new_password:password()});
        setMode('Sign in');setPassword('');setError('Password reset. Sign in with your new password.');
      } else {
        const result=await api<{user:User}>('/auth/'+(mode()==='Create account'?'register':'login'),{username:username(),password:password(),...(mode()==='Create account'?{accept_policies:accepted(),terms_version:policies.version,privacy_version:policies.version}:{})});
        await props.onLogin(result.user);props.onClose();
      }
    } catch(err) { setError(err instanceof Error?err.message:'Please try again.'); } finally {setBusy(false);}
  }
  return <Modal title="Welcome backstage." onClose={props.onClose}><p class="muted">The same account, cards, and progress you use in the Android game.</p><Tabs values={['Sign in','Create account','Recover']} active={mode()} select={v=>{setMode(v);setError('');setAccepted(false);}}/><form class="stack" onSubmit={submit}><label>Username<input autocomplete="username" minlength={3} maxlength={24} pattern="[A-Za-z0-9_]+" required value={username()} onInput={e=>setUsername(e.currentTarget.value)} placeholder="Your player name"/></label>{mode()==='Recover'&&<label>Recovery code<input required autocomplete="off" value={recovery()} onInput={e=>setRecovery(e.currentTarget.value)} placeholder="One of your saved recovery codes"/></label>}<label>{mode()==='Recover'?'New password':'Password'}<input type="password" autocomplete={mode()==='Sign in'?'current-password':'new-password'} minlength={mode()==='Sign in'?1:8} maxlength={128} required value={password()} onInput={e=>setPassword(e.currentTarget.value)}/></label>{mode()==='Create account'&&<><p class="fan-notice">{policies.notice}</p><p class="scam-notice">{policies.scam_warning}</p><label class="policy-consent"><input name="accept_policies" type="checkbox" required checked={accepted()} disabled={busy()} onChange={e=>setAccepted(e.currentTarget.checked)}/><span>I agree to the <button type="button" class="policy-link" onClick={e=>{e.preventDefault();setLegal('terms');}}>Terms & Conditions</button> and acknowledge the <button type="button" class="policy-link" onClick={e=>{e.preventDefault();setLegal('privacy');}}>Privacy Policy</button>.</span></label></>}{error()&&<p class="notice" role="alert">{error()}</p>}<button class="button primary" disabled={busy()||(mode()==='Create account'&&!accepted())}>{busy()?'Opening your backstage…':mode()}<Icon name="arrow"/></button><small class="muted">Login stays with you for 30 days. Sign out anytime from your profile.</small></form><div class="policy-footer"><button type="button" class="policy-link" onClick={()=>setLegal('terms')}>Terms & Conditions</button><button type="button" class="policy-link" onClick={()=>setLegal('privacy')}>Privacy Policy</button></div>{legal()&&<LegalPolicy kind={legal()!} onClose={()=>setLegal(null)}/>}</Modal>;
}
