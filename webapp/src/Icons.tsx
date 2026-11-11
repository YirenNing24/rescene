export function Icon(props: {name: string; size?: number}) {
  const paths: Record<string,string> = {
    home:'M3 10 12 3l9 7v11h-6v-7H9v7H3Z', card:'M6 3h13v17H6zM3 7v15h12M10 7h5M10 11h5M10 15h3',
    bag:'M5 7h14l2 14H3ZM8 8V6a4 4 0 0 1 8 0v2', gift:'M3 8h18v4H3ZM5 12v9h14v-9M12 8v13M12 8C3 9 5 1 9 4ZM12 8c9 1 7-7 3-4Z',
    music:'M9 18V5l12-2v13M9 8l12-2M9 18c0 4-6 4-6 1s6-4 6-1ZM21 16c0 4-6 4-6 1s6-4 6-1Z',
    people:'M16 21v-3a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v3M9 10a4 4 0 1 0 0-8 4 4 0 0 0 0 8ZM17 3a4 4 0 0 1 0 7M22 21v-3a4 4 0 0 0-3-3',
    user:'M20 21v-3a8 8 0 0 0-16 0v3M12 10a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z',
    arrow:'M5 12h14M13 6l6 6-6 6', down:'M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5', star:'m12 2 3 6 7 1-5 5 1 8-6-4-6 4 1-8-5-5 7-1Z',
    heart:'M12 21 3 12C-3 4 8-1 12 6c4-7 15-2 9 6Z', message:'M21 16a3 3 0 0 1-3 3H8l-5 3V5a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3ZM7 7h10M7 12h7',
    trophy:'M7 3h10v7a5 5 0 0 1-10 0ZM7 5H3v3a5 5 0 0 0 5 5M17 5h4v3a5 5 0 0 1-5 5M12 15v6M8 21h8',
    close:'m6 6 12 12M6 18 18 6', menu:'M3 6h18M3 12h18M3 18h18', search:'M10 17a7 7 0 1 0 0-14 7 7 0 0 0 0 14Zm5-2 7 7',
    check:'m4 12 5 5L20 6', lock:'M5 10h14v12H5ZM8 10V6a4 4 0 0 1 8 0v4', wallet:'M3 5h17v16H3ZM3 5V3h14v2M15 11h6v5h-6Z',
    settings:'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8ZM9 2h6l1 4 4 1 3 5-3 5-4 1-1 4H9l-1-4-4-1-3-5 3-5 4-1Z',
    spark:'m12 2 2 7 8 3-8 3-2 7-2-7-8-3 8-3Z', logout:'M9 3H3v18h6M10 12h12m-5-5 5 5-5 5', bolt:'m14 2-9 12h7l-2 8 9-12h-7Z', copy:'M8 8h13v13H8ZM16 3H3v13', flag:'M5 22V3h14l-3 5 3 5H5', refresh:'M21 11a9 9 0 1 0-2 7M21 3v8h-8'
  };
  return <svg width={props.size ?? 20} height={props.size ?? 20} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d={paths[props.name] ?? paths.spark}/></svg>;
}
