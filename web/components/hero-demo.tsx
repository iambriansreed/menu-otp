import { menuBarTime } from '../menu-bar-time';

/**
 * The hero: a drawn menu bar with Menu OTP's status icon, and the real menu under it.
 * web/hero-demo.ts animates it: a pointer clicks the icon, the menu opens, the highlight
 * follows the pointer down the accounts, a click shows "Copied". The frames are real
 * screenshots from the app's snapshot mode (see web/README.md); the menu bar is drawn
 * here so it shows nothing from anyone's actual Mac.
 *
 * As rendered (no JavaScript) it's a still: the menu open under the icon, no pointer.
 * hero-demo.ts starts from there: one pass on its own (none with Reduce Motion), then a
 * play button for each pass after.
 */
export function HeroDemo() {
    return (
        <div class="hero-demo">
            {/* The drawn screen is one image to assistive tech; the play button sits
                outside it, since an image's contents are hidden from them */}
            <div
                class="demo-screen"
                role="img"
                aria-label="Menu OTP's icon in the macOS menu bar. Clicking it opens a menu of accounts with their service icons; clicking an account copies its code and shows it with the word Copied."
            >
                {/* Right-aligned like a real menu bar, in macOS 26's order: third-party icons
                    (Menu OTP) left of the system ones, drawn here as SVGs of the defaults */}
                <div class="menubar" aria-hidden="true">
                    <span class="menubar-item menubar-otp active" data-demo="icon">
                        <span class="menubar-glyph"></span>
                    </span>
                    {/* Accessibility */}
                    <span class="menubar-item menubar-optional">
                        <svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round">
                            <circle cx="8" cy="8" r="6.6" />
                            <circle cx="8" cy="4.9" r="0.9" fill="currentColor" stroke="none" />
                            <path d="M4.9 6.9 8 7.6l3.1-.7M8 7.6v2.2m0 0-1.6 2.6M8 9.8l1.6 2.6" />
                        </svg>
                    </span>
                    {/* Bluetooth */}
                    <span class="menubar-item">
                        <svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">
                            <path d="M4.8 5.2 11.2 10.8 8 13.6V2.4l3.2 2.8-6.4 5.6" />
                        </svg>
                    </span>
                    {/* Sound */}
                    <span class="menubar-item">
                        <svg viewBox="0 0 18 16" width="18" height="16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">
                            <path d="M2 6h2.6L8 3.2v9.6L4.6 10H2V6Z" fill="currentColor" />
                            <path d="M10.6 5.8a3 3 0 0 1 0 4.4M12.6 3.8a5.8 5.8 0 0 1 0 8.4" />
                        </svg>
                    </span>
                    {/* Battery */}
                    <span class="menubar-item">
                        <svg viewBox="0 0 24 12" width="24" height="12" fill="none" stroke="currentColor" stroke-width="1.2">
                            <rect x="0.6" y="0.6" width="20" height="10.8" rx="3" opacity="0.6" />
                            <rect x="2.4" y="2.4" width="13" height="7.2" rx="1.6" fill="currentColor" stroke="none" />
                            <path d="M22.4 4.2v3.6" stroke-linecap="round" opacity="0.6" />
                        </svg>
                    </span>
                    {/* Focus */}
                    <span class="menubar-item menubar-optional menubar-dim">
                        <svg viewBox="0 0 16 16" width="15" height="15" fill="currentColor">
                            <path d="M9.6 1.6a6.6 6.6 0 1 0 4.8 10.6A5.6 5.6 0 0 1 9.6 1.6Z" />
                        </svg>
                    </span>
                    {/* Wi-Fi */}
                    <span class="menubar-item">
                        <svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor">
                            <path d="M8 12.6 5.9 10.5a3 3 0 0 1 4.2 0L8 12.6Zm-3.4-3.4-1.1-1.1a6.4 6.4 0 0 1 9 0l-1.1 1.1a4.8 4.8 0 0 0-6.8 0ZM2.2 6.8 1.1 5.7a9.8 9.8 0 0 1 13.8 0l-1.1 1.1a8.2 8.2 0 0 0-11.6 0Z" />
                        </svg>
                    </span>
                    {/* User */}
                    <span class="menubar-item menubar-optional">
                        <svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.3">
                            <circle cx="8" cy="8" r="6.6" />
                            <circle cx="8" cy="6.4" r="2.2" />
                            <path d="M3.9 12.6a4.9 4.9 0 0 1 8.2 0" stroke-linecap="round" />
                        </svg>
                    </span>
                    {/* Spotlight */}
                    <span class="menubar-item menubar-optional">
                        <svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
                            <circle cx="6.8" cy="6.8" r="4.6" />
                            <path d="m10.2 10.2 4 4" />
                        </svg>
                    </span>
                    {/* Control Center */}
                    <span class="menubar-item">
                        <svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.3">
                            <rect x="1.6" y="2.2" width="12.8" height="5" rx="2.5" />
                            <circle cx="11.9" cy="4.7" r="1.2" fill="currentColor" stroke="none" />
                            <rect x="1.6" y="8.8" width="12.8" height="5" rx="2.5" />
                            <circle cx="4.1" cy="11.3" r="1.2" fill="currentColor" stroke="none" />
                        </svg>
                    </span>
                    {/* The visitor's own date and time (hero-demo.ts keeps it current); the build
                        time until then */}
                    <span class="menubar-clock" data-demo="clock">
                        {menuBarTime(new Date())}
                    </span>
                </div>
                {/* Desktop folders, under the menu frames. Projects sits top right, where
                    Finder puts icons and the open menu never reaches, a little off the grid;
                    Death Star Plans hides exactly under the menu, seen only when it closes */}
                <div class="desktop" aria-hidden="true">
                    <DesktopFolder class="desktop-projects" label="Projects" />
                    <DesktopFolder class="desktop-secret" label="Death Star Plans" />
                </div>
                <div class="demo-stage" aria-hidden="true">
                    <img class="demo-frame demo-menu shown" data-demo="menu" src="hero-menu.png" alt="" width="353" height="319" />
                    <img class="demo-frame demo-menu" data-demo="row-0" src="hero-row-0.png" alt="" width="353" height="319" />
                    <img class="demo-frame demo-menu" data-demo="row-1" src="hero-row-1.png" alt="" width="353" height="319" />
                    <img class="demo-frame demo-copied" data-demo="copied" src="hero-copied.png" alt="" width="310" height="57" />
                </div>
                <svg class="demo-cursor" data-demo="cursor" viewBox="0 0 18 26" width="18" height="26" aria-hidden="true">
                    <path d="M1.5 1.5v19.2l4.6-4.4 3 6.9 3.4-1.5-3-6.8h6.3L1.5 1.5Z" fill="#000" stroke="#fff" stroke-width="1.4" stroke-linejoin="round" />
                </svg>
            </div>
            {/* hero-demo.ts shows it when the animation pauses with the menu open */}
            <button class="demo-play" type="button" data-demo="play" aria-label="Play the demo again" hidden>
                <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
                    <path d="M5 3.2v9.6a.6.6 0 0 0 .9.5l7.6-4.8a.6.6 0 0 0 0-1L5.9 2.7a.6.6 0 0 0-.9.5Z" fill="currentColor" />
                </svg>
            </button>
        </div>
    );
}

/** A folder on the desktop as Finder draws one: the blue folder, its name below. */
function DesktopFolder(props: { class: string; label: string }) {
    return (
        <div class={`desktop-folder ${props.class}`}>
            <svg viewBox="0 0 64 52" width="56" height="46">
                <path d="M4 8a4 4 0 0 1 4-4h15.2a4 4 0 0 1 3 1.3L29.6 9H56a4 4 0 0 1 4 4v3H4V8Z" fill="#5aa7ec" />
                <rect x="4" y="13" width="56" height="35" rx="4" fill="#79bdf6" />
                <rect x="4" y="13" width="56" height="3" rx="1.5" fill="#a9d6fb" opacity="0.8" />
            </svg>
            <span>{props.label}</span>
        </div>
    );
}
