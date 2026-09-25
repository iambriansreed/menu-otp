import { menuBarTime } from './menu-bar-time';

/**
 * Where the pointer goes inside a menu frame (hero-menu.png and friends, 353 CSS px wide):
 * a point on the first two account rows, the ones the demo passes over and clicks.
 * Measured from the frames; scaled when a narrow screen shrinks the image.
 */
const MENU_WIDTH = 353;
/** .menubar's height in style.css */
const BAR_HEIGHT = 30;
const ROW_X = 150;
const ROW_Y = [61, 94];

const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * Animates web/components/hero-demo.tsx. It starts with the menu open under the icon. A
 * pass: the highlight follows the pointer down two accounts, a click shows "Copied", a
 * click elsewhere closes the menu, the pointer clicks the icon again, and it stops with
 * the menu open and a play button, which runs another pass. The first pass plays on its
 * own, except with Reduce Motion, where it starts stopped. The clock keeps the visitor's
 * own time either way.
 */
export function initHeroDemo() {
    const root = document.querySelector<HTMLElement>('.hero-demo');
    if (!root) return;
    const part = (name: string) => root.querySelector<HTMLElement>(`[data-demo="${name}"]`)!;
    const icon = part('icon');
    const cursor = part('cursor');
    const clock = part('clock');
    const menu = part('menu') as HTMLImageElement;
    const frames = ['menu', 'row-0', 'row-1', 'copied'].map(part);

    // The clock: now, then on each minute
    const tick = () => {
        clock.textContent = menuBarTime(new Date());
        setTimeout(tick, 60_000 - (Date.now() % 60_000));
    };
    tick();

    // The menu hangs under the icon's centre, kept inside the frame, as the app keeps it
    // on screen. Everything the pointer targets is measured from the same layout.
    const layout = () => {
        const box = root.getBoundingClientRect();
        const iconBox = icon.getBoundingClientRect();
        const iconX = iconBox.left + iconBox.width / 2 - box.left;
        const barHeight = BAR_HEIGHT;
        const clamp = (left: number, width: number) => Math.min(Math.max(left, 8), box.width - width - 8);
        const menuWidth = menu.getBoundingClientRect().width || MENU_WIDTH;
        const menuLeft = clamp(iconX - menuWidth / 2, menuWidth);
        const copiedWidth = part('copied').getBoundingClientRect().width || 310;
        root.style.setProperty('--menu-left', `${menuLeft}px`);
        root.style.setProperty('--copied-left', `${clamp(iconX - copiedWidth / 2, copiedWidth)}px`);
        const scale = menuWidth / MENU_WIDTH;
        return {
            icon: { x: iconX, y: barHeight / 2 + 2 },
            rows: ROW_Y.map((y) => ({ x: menuLeft + ROW_X * scale, y: barHeight + y * scale })),
            away: { x: Math.min(box.width - 40, menuLeft + menuWidth + 30), y: barHeight + 250 * scale },
            start: { x: box.width - 60, y: barHeight + 230 * scale },
        };
    };
    let points = layout();
    window.addEventListener('resize', () => (points = layout()));

    // Reduce Motion: nothing moves until the visitor asks, by pressing play
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    const show = (name: string | null) => {
        for (const frame of frames) frame.classList.toggle('shown', frame.dataset.demo === name);
        icon.classList.toggle('active', name !== null);
    };
    const move = async (to: { x: number; y: number }, ms: number) => {
        cursor.style.transition = ms ? `transform ${ms}ms cubic-bezier(0.4, 0, 0.2, 1)` : 'none';
        cursor.style.transform = `translate(${to.x}px, ${to.y}px)`;
        await wait(ms);
    };
    // A real pointer doesn't move when it clicks, so neither does this one: a click is
    // just the beat before what it does
    const click = () => wait(120);

    // Paused with the menu open: the play button shows, and it or a click anywhere on the
    // demo resolves this. The button is the keyboard and screen reader way in.
    const play = part('play') as HTMLButtonElement;
    const pause = () =>
        new Promise<void>((resolve) => {
            play.hidden = false;
            root.classList.add('paused');
            const resume = () => {
                play.hidden = true;
                root.classList.remove('paused');
                root.removeEventListener('click', resume);
                resolve();
            };
            // The button is inside root, so one listener on root covers both
            root.addEventListener('click', resume);
        });

    // Runs only while the hero is on screen and the tab is visible
    let visible = true;
    new IntersectionObserver(([entry]) => (visible = entry.isIntersecting)).observe(root);
    const whenVisible = async () => {
        while (!visible || document.hidden) await wait(400);
    };

    root.classList.add('animated');
    const loop = async () => {
        // Starts as the page rendered it: the menu open, the pointer on the icon it just
        // clicked. The first pass plays by itself after a beat, unless Reduce Motion is
        // on; every pass after that waits for play.
        await move(points.icon, 0);
        let autoplay = !reduceMotion;
        for (;;) {
            if (autoplay) {
                await wait(900);
                autoplay = false;
            } else {
                await pause();
            }
            await whenVisible();
            await move(points.rows[0], 550);
            show('row-0');
            await wait(380);
            await move(points.rows[1], 300);
            show('row-1');
            await wait(550);
            await click();
            show('copied');
            await wait(2200);
            await move(points.away, 600);
            await click();
            show(null);
            await wait(1000);
            await move(points.start, 0);
            await wait(500);
            await move(points.icon, 800);
            await click();
            // Back where it started: the menu open, paused again
            show('menu');
        }
    };
    void loop();
}
