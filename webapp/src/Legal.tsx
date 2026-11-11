import policies from '../../assets/legal/policies.json';
import { Modal } from './ui';
export { policies };
export type PolicyKind = 'terms' | 'privacy';
export function LegalPolicy(props: {kind: PolicyKind; onClose: () => void}) {
  return <Modal title={policies[props.kind].title} onClose={props.onClose}><article class="policy-copy"><p class="muted">Updated {policies.updated} · Version {policies.version}</p>{policies[props.kind].sections.map(section=><section><h3>{section.title}</h3><p>{section.body}</p></section>)}<p>Contact: <a class="policy-link" href={'mailto:'+policies.contact}>{policies.contact}</a></p></article></Modal>;
}
