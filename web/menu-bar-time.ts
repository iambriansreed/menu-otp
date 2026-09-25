/**
 * "Thu Sep 24 7:31 PM", as the macOS menu bar writes the date and time, with the wider
 * gap it leaves before the time. Used by the hero's drawn menu bar at build time and by
 * hero-demo.ts in the browser, which keeps it on the visitor's own clock.
 */
export function menuBarTime(date: Date): string {
    const day = date.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
    const time = date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
    // "Thu, Sep 24" -> "Thu Sep 24"; U+2002 (an en space) for the gap before the time
    return `${day.replace(',', '')} ${time}`;
}
