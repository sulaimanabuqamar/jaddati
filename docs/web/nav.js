// Where you are, and how you got here.
//
// Kept apart from the screens so a screen can push another one without the two
// files importing each other. The tab and the selected person outlive a
// language change on purpose: switching language rebuilds everything, and
// losing your place because you tapped the globe is its own small betrayal.

import { player } from "./ui.js?v=b66be76375";
import { prefs } from "./prefs.js?v=b66be76375";

export const TABS = ["people", "letters", "you"];

export const nav = {
  tab: "people",
  personId: null,
  /** One stack per tab. The app's pager keeps all three alive, so a tab still
   *  remembers where you were when you come back to it. */
  stacks: { people: [], letters: [], you: [] },
};

Object.defineProperty(nav, "stack", { get() { return nav.stacks[nav.tab]; } });

// Saved and Books were tabs that did nothing until you had first tapped into a
// person — two thirds of the rail dead on arrival. A phone that still has one
// of those names stored would land on a tab that no longer exists and render
// nothing, so anything unrecognised falls back to People.
const storedTab = prefs.get("jaddati.tab");
nav.tab = TABS.includes(storedTab) ? storedTab : "people";
nav.personId = prefs.get("jaddati.person") || null;

export function remember() {
  prefs.set("jaddati.tab", nav.tab);
  if (nav.personId) prefs.set("jaddati.person", nav.personId);
  else prefs.remove("jaddati.person");
}

let renderer = () => {};
export const setRenderer = fn => { renderer = fn; };
export const render = () => renderer();

export function push(screen, props) { nav.stack.push({ screen, props }); render(); }
/** Swap the screen you are on for another, rather than stacking a second copy.
 *  Switching what you are asking for is not going somewhere new, and Back
 *  should still mean "out of here", not "the last thing I tried". */
export function replace(screen, props) {
  player.stop();
  if (!nav.stack.length) nav.stack.push({ screen, props });
  else nav.stack[nav.stack.length - 1] = { screen, props };
  render();
}
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
