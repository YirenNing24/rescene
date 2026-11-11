// Lucide icon geometry, ISC license. See src/lucide-LICENSE.
import type { JSX } from "@solidjs/web";

type Props = JSX.SvgSVGAttributes<SVGSVGElement> & { size?: number };

export function ArrowUpRight(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path d={"M7 7h10v10"} />
      <path d={"M7 17 17 7"} />
    </svg>
  );
}

export function ArrowRight(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path d={"M5 12h14"} />
      <path d={"m12 5 7 7-7 7"} />
    </svg>
  );
}

export function Search(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path d={"m21 21-4.34-4.34"} />
      <circle cx={"11"} cy={"11"} r={"8"} />
    </svg>
  );
}

export function X(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path d={"M18 6 6 18"} />
      <path d={"m6 6 12 12"} />
    </svg>
  );
}

export function Menu(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path d={"M4 5h16"} />
      <path d={"M4 12h16"} />
      <path d={"M4 19h16"} />
    </svg>
  );
}

export function Heart(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path
        d={
          "M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5"
        }
      />
    </svg>
  );
}

export function Play(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path
        d={
          "M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"
        }
      />
    </svg>
  );
}

export function Sparkles(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path
        d={
          "M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z"
        }
      />
      <path d={"M20 2v4"} />
      <path d={"M22 4h-4"} />
      <circle cx={"4"} cy={"20"} r={"2"} />
    </svg>
  );
}

export function Music2(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <circle cx={"8"} cy={"18"} r={"4"} />
      <path d={"M12 18V2l7 4"} />
    </svg>
  );
}

export function Layers(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path
        d={
          "M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"
        }
      />
      <path
        d={
          "M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"
        }
      />
      <path
        d={
          "M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"
        }
      />
    </svg>
  );
}

export function Check(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path d={"M20 6 9 17l-5-5"} />
    </svg>
  );
}

export function RotateCcw(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path d={"M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"} />
      <path d={"M3 3v5h5"} />
    </svg>
  );
}

export function ExternalLink(props: Props) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {...props}
      width={props.size ?? 24}
      height={props.size ?? 24}
    >
      <path d={"M15 3h6v6"} />
      <path d={"M10 14 21 3"} />
      <path d={"M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"} />
    </svg>
  );
}
