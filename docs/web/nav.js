// Where you are, and how you got here.
//
// Kept apart from the screens so a screen can push another one without the two
// files importing each other. The tab and the selected person outlive a
// language change on purpose: switching language rebuilds everything, and
// losing your place because you tapped the globe is its own small betrayal.

import { player } from "./ui.js";

export const nav = {
  tab: "people",
  personId: null,
  /** One stack per tab. The app's pager keeps all three alive, so a tab still
   *  remembers where you were when you come back to it. */
  stacks: { people: [], saved: [], books: [] },
};

Object.defineProperty(nav, "stack", { get() { return nav.stacks[nav.tab]; } });

try {
  nav.tab = localStorage.getItem("jaddati.tab") || "people";
  nav.personId = localStorage.getItem("jaddati.person") || null;
} catch { /* storage blocked; defaults are fine */ }

export function remember() {
  try {
    localStorage.setItem("jaddati.tab", nav.tab);
    if (nav.personId) localStorage.setItem("jaddati.person", nav.personId);
    else localStorage.removeItem("jaddati.person");
  } catch {}
}

let renderer = () => {};
export const setRenderer = fn => { renderer = fn; };
export const render = () => renderer();

export function push(screen, props) { nav.stack.push({ screen, props }); render(); }
export function pop() { player.stop(); nav.stack.pop(); render(); }
export function popTo(depth) { player.stop(); nav.stack.length = depth; render(); }
export function goTab(tab) {
  player.stop();
  // Tapping the tab you are already on goes back to its root, the way a tab
  // bar behaves everywhere else.
  if (nav.tab === tab) nav.stack.length = 0;
  nav.tab = tab;
  render();
}
