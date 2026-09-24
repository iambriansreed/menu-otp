#!/usr/bin/env node
/**
 * @file Runs the demo app and the website's dev server together, as `npm run dev`, and
 * restarts the demo app whenever a file under `app/` changes.
 *
 * Both children are started in their **own process groups** (`detached: true`) and are
 * killed by group on the way out. That matters for the app in particular:
 * `app/scripts/demo.sh` is a shell script that builds and then `exec`s the real binary,
 * so a plain `kill` aimed at the pid we know can leave the app running. An orphaned copy
 * then holds the single-instance lock and the next `npm run dev` quits silently.
 *
 * This is what `npm run dev` calls, so it must never call `npm run dev` back.
 *
 * @module dev
 */

import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

process.chdir(path.join(import.meta.dirname, '..'));

/**
 * A child started in its own process group.
 *
 * @typedef {object} Child
 * @property {string} name For messages.
 * @property {import('node:child_process').ChildProcess} process The spawned process.
 */

/** @type {Child[]} */
const children = [];

/** Guards against re-entering {@link stopAll} from a child's own exit handler. */
let stopping = false;

/**
 * Signals a child's whole process group. Failures are ignored on purpose: the child has
 * usually exited already, and its group no longer exists.
 *
 * @param {Child} child
 * @param {NodeJS.Signals} signal
 * @returns {void}
 */
function signalGroup(child, signal) {
    if (child.process.pid === undefined) return;
    try {
        // Negative pid: the group, not just the leader
        process.kill(-child.process.pid, signal);
    } catch {
        // already gone
    }
}

/**
 * Signals every child's process group, then exits.
 *
 * @param {number} code Exit code for this process.
 * @returns {never}
 */
function stopAll(code) {
    stopping = true;
    for (const child of children) signalGroup(child, 'SIGTERM');
    process.exit(code);
}

/**
 * Starts a command in its own process group, wired to this terminal.
 *
 * `detached: true` is what makes the child a group leader, so {@link stopAll} can signal
 * the whole group. The trade-off is that a detached child does **not** receive the
 * terminal's Ctrl+C, which is why the signal handlers below forward it explicitly.
 *
 * @param {string} name A label for messages.
 * @param {string} command The executable to run.
 * @param {string[]} args Its arguments.
 * @param {object} [options]
 * @param {string} [options.cwd] Directory to run in, relative to the repository root.
 * @param {(code: number | null, signal: NodeJS.Signals | null) => boolean} [options.onExit]
 *   Called when the child exits; returning true means it was handled and the session
 *   carries on. Otherwise the first child to stop takes the session with it.
 * @returns {Child}
 */
function start(name, command, args, { cwd, onExit } = {}) {
    const child = { name, process: spawn(command, args, { cwd, stdio: 'inherit', detached: true }) };
    child.process.on('exit', (code, signal) => {
        const index = children.indexOf(child);
        if (index !== -1) children.splice(index, 1);
        if (stopping || onExit?.(code, signal)) return;
        // Ctrl+C in either half, or a crash, ends the whole thing rather than leaving one
        // running unattended.
        const how = signal ? `signal ${signal}` : `code ${code}`;
        console.error(`\n${name} exited (${how}); stopping.`);
        stopAll(typeof code === 'number' ? code : 1);
    });
    children.push(child);
    return child;
}

for (const signal of /** @type {const} */ (['SIGINT', 'SIGTERM'])) {
    process.on(signal, () => stopAll(signal === 'SIGINT' ? 130 : 143));
}

// MARK: The demo app, restarted on changes under app/

/** @type {Child | undefined} */
let app;

/** True from asking the running app to stop until the new one has been started. */
let restarting = false;

/**
 * Starts `demo.sh` (build, then run). A failed build or a crash leaves the session
 * running, waiting for the next change to try again; quitting the app from its own menu
 * (exit code 0) still ends the session, as it did before this watched anything.
 *
 * @returns {void}
 */
function startApp() {
    app = start('the demo app', 'app/scripts/demo.sh', [], {
        onExit(code, signal) {
            app = undefined;
            if (restarting) return true;
            if (code === 0) return false;
            const how = signal ? `signal ${signal}` : `code ${code}`;
            console.error(`\nthe demo app exited (${how}); waiting for a change under app/ to try again.`);
            return true;
        },
    });
}

/**
 * Stops the running app (if any), waits for it to exit so its instance lock is free,
 * then starts it again. A change that arrives mid-restart needs nothing more: the new
 * run builds after it.
 *
 * @returns {void}
 */
function restartApp() {
    if (restarting) return;
    console.error('\napp/ changed; restarting the demo app.');
    const running = app;
    if (!running) {
        startApp();
        return;
    }
    restarting = true;
    running.process.once('exit', () => {
        clearTimeout(force);
        restarting = false;
        startApp();
    });
    signalGroup(running, 'SIGTERM');
    // It should go at once; if it hangs, don't wait forever
    const force = setTimeout(() => signalGroup(running, 'SIGKILL'), 3000);
}

/**
 * Whether a change under app/ should restart the app. Build output is skipped (the
 * restart's own build writes there, which would loop), and so are dotfiles such as
 * .DS_Store and editors' swap files.
 *
 * @param {string} file Path relative to app/.
 * @returns {boolean}
 */
function isWatched(file) {
    const parts = file.split(path.sep);
    return parts[0] !== 'build' && !parts.some((part) => part.startsWith('.'));
}

/** @type {NodeJS.Timeout | undefined} */
let debounce;

// Recursive fs.watch is native on macOS. The debounce folds a burst (save-all, a git
// checkout) into one restart.
fs.watch('app', { recursive: true }, (_event, file) => {
    if (!file || !isWatched(file)) return;
    clearTimeout(debounce);
    debounce = setTimeout(restartApp, 300);
});

// The app first: it builds before it runs, so starting it now overlaps that build with
// the dev server coming up.
startApp();

// Skrapa runs every command from the skrapa root, and this uses the binary that
// package-lock.json pins rather than whatever `npx` would resolve.
start('the dev server', path.resolve('node_modules/.bin/skrapa'), ['dev'], { cwd: 'web' });
