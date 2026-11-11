import type { ParentProps } from "solid-js";
import { HydrationScript } from "@solidjs/web";

export default function Document(props: ParentProps) {
  return (
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="theme-color" content="#0d0e11" />
        <meta
          name="description"
          content="An independent fan space for RESCENE and REMINE. Discover all five members, explore the music, play the fan quiz, and collect your favorite PULSE portraits."
        />
        <link rel="icon" href="/favicon.svg" />
        <link rel="canonical" href="https://remineph.online/" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossorigin="anonymous"
        />
        <title>RESCENE — Five voices. Endless scenes.</title>
        <HydrationScript />
      </head>
      <body>{props.children}</body>
    </html>
  );
}
