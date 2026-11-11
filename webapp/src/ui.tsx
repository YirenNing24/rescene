import { onSettled } from 'solid-js';
import type { JSX } from '@solidjs/web';
import { Icon } from './Icons';
import { photoURL } from './api';
import type { Photo } from './types';
export function Empty(props: {icon?: string; title: string; text: string; children?: JSX.Element}) {
  return <div class="empty"><Icon name={props.icon ?? 'spark'} size={32}/><h3>{props.title}</h3><p>{props.text}</p>{props.children}</div>;
}
export function Avatar(props: {photo?: Photo | null; name: string; online?: boolean; large?: boolean}) {
  return <span class={'avatar'+(props.large?' large':'')}><span>{props.photo ? <img src={photoURL(props.photo.url)} alt={props.name}/> : props.name.slice(0,1).toUpperCase()}</span>{props.online && <i/>}</span>;
}
export function Modal(props: {title: string; onClose: () => void; children: JSX.Element; wide?: boolean}) {
  let ref!: HTMLDialogElement;
  onSettled(() => { ref.showModal(); return () => ref.close(); });
  return <dialog ref={ref} class={props.wide?'modal wide':'modal'} onCancel={e=>{e.preventDefault();props.onClose();}} onClick={e=>{if(e.target===ref)props.onClose();}}><div class="modal-inner"><header><div><p class="eyebrow">RESCENE / RHYTHM</p><h2>{props.title}</h2></div><button class="icon-button" aria-label="Close dialog" onClick={props.onClose}><Icon name="close"/></button></header>{props.children}</div></dialog>;
}
export function SectionTitle(props: {eyebrow: string; title: string; text?: string; children?: JSX.Element}) {
  return <header class="section-title"><div><p class="eyebrow">{props.eyebrow}</p><h1>{props.title}</h1>{props.text && <p>{props.text}</p>}</div>{props.children}</header>;
}
export function Tabs(props: {values: string[]; active: string; select: (value: string) => void}) {
  return <div class="tabs" role="tablist">{props.values.map(value=><button role="tab" aria-selected={props.active===value?'true':'false'} class={props.active===value?'selected':''} onClick={()=>props.select(value)}>{value}</button>)}</div>;
}
export function ProgressBar(props: {value: number; max: number}) {
  return <div class="progress-track" role="progressbar" aria-valuenow={props.value} aria-valuemin={0} aria-valuemax={props.max}><span style={{width:Math.min(100,props.value/Math.max(props.max,1)*100)+'%'}}/></div>;
}
