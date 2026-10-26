#!/usr/bin/env python3
"""Assign every umbrella test file to a per-module test target, from analyze.py's output.

The rule (owner request B-TC1-1, 2026-10-12; scripted per the owner's 2026-10-14 ask). What a file needs is what
it uses itself and what the helpers it uses need, to the end of the chain: a test using a Table fixture needs
TUITables, as the fixture's support target depends on it. By the modules at the top of that:

- none above the base (TUIFoundation and what it re-exports): TUIFoundationTests;
- TUIApp and none above the base: TUIAppTests;
- one feature module (Lists, Tables, Menus...), with or without TUIApp: that module's test target, which then
  depends on TUIApp too where one of its files needs it — an edit to a feature still rebuilds only its own
  tests and the integration ones;
- two feature modules: TUIIntegrationTests, the one target that keeps depending on everything.

A support file (TUITestSupport), or a test-target file that holds no tests, is a helper: it goes to the support
target of the same level — the base TUITestSupport, TUIAppTestSupport, a feature's own, or
TUIIntegrationTestSupport — which every test target that can use it can see.

Test files that share a helper declared in one of them (a test target can't be depended on) land together, in
the target of what the group needs between them.

Usage: plan.py ANALYSIS.json [--out PLAN.json]
"""
import argparse, collections, glob, json, sys

BASE = {"TUICore", "TUIStyling", "TUIView", "TUIImage", "TUIStrings", "TUITerminalHost",
        "TUIFoundation"}
APP = "TUIApp"
SUPPORT = "TUITestSupport"


def closure(graph, module):
    found, stack = set(), [module]
    while stack:
        for dep in graph.get(stack.pop(), []):
            if dep not in found:
                found.add(dep)
                stack.append(dep)
    return found


def tops_of(modules, graph):
    """The modules no other of `modules` already depends on."""
    return sorted(m for m in modules if not any(m in closure(graph, o) for o in modules if o != m))


def level(tops):
    """The module a file's tests sit with: TUIFoundation, TUIApp, one feature, or None for Integration."""
    features = sorted(t for t in tops if t not in BASE and t != APP)
    if not features:
        return APP if APP in tops else "TUIFoundation"
    if len(features) == 1:
        return features[0]
    return None


def test_target(tops):
    return f"{level(tops) or 'TUIIntegration'}Tests"


def support_target(tops):
    module = level(tops)
    if module == "TUIFoundation":
        return SUPPORT
    return f"{module or 'TUIIntegration'}TestSupport"


def has_tests(key):
    """Whether the test file `key` (TARGET/Name) declares a test, read from its source."""
    target, name = key.split("/")
    for path in glob.glob(f"Tests/{target}/**/{name}.swift", recursive=True):
        text = open(path).read()
        return "@Test" in text or "@Suite" in text
    return True


class UnionFind:
    def __init__(self):
        self.parent = {}

    def find(self, x):
        self.parent.setdefault(x, x)
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        self.parent[self.find(a)] = self.find(b)

    def components(self):
        found = collections.defaultdict(list)
        for x in self.parent:
            found[self.find(x)].append(x)
        return [m for m in found.values() if len(m) > 1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("analysis")
    ap.add_argument("--out", default="test-split-plan.json")
    args = ap.parse_args()
    analysis = json.load(open(args.analysis))
    files, graph = analysis["files"], analysis["graph"]
    helper_file = {key: info["target"] == SUPPORT or not has_tests(key) for key, info in files.items()}
    # What each file needs, its helpers' needs folded in, to a fixpoint (helpers can use each other in a cycle).
    needs = {key: set(info["modules"]) | set(info["tops"]) for key, info in files.items()}
    changed = True
    while changed:
        changed = False
        for key, info in files.items():
            for helper in info["helpers"]:
                if helper in needs and not needs[helper] <= needs[key]:
                    needs[key] |= needs[helper]
                    changed = True
    tops = {key: tops_of(needs[key] - {"TUIIntegration"}, graph) + (
        ["TUIIntegration"] if "TUIIntegration" in needs[key] else []) for key in files}

    def placed(key):
        if "TUIIntegration" in tops[key]:
            return f"TUIIntegration{'TestSupport' if helper_file[key] else 'Tests'}"
        return support_target(tops[key]) if helper_file[key] else test_target(tops[key])

    plan = {key: placed(key) for key in files}
    # Test files sharing a helper declared in a test file land together, in the target of what they need between
    # them.
    groups = UnionFind()
    for key, info in files.items():
        for helper in info["helpers"]:
            if not helper_file[helper] and not helper_file[key]:
                groups.union(key, helper)
    for members in groups.components():
        joined = set()
        for member in members:
            joined |= set(tops[member])
        target = ("TUIIntegrationTests" if "TUIIntegration" in joined
                  else test_target(tops_of(joined - {"TUIIntegration"}, graph)))
        for member in members:
            plan[member] = target
    # Every helper edge must be visible: to a support target, or within the target.
    broken = [(key, helper) for key, info in files.items() for helper in info["helpers"]
              if plan[helper] != plan[key] and not plan[helper].endswith("TestSupport")]
    json.dump({"plan": plan, "tops": tops, "broken": broken}, open(args.out, "w"), indent=1, sort_keys=True)
    tally = collections.Counter(plan.values())
    for target, count in sorted(tally.items(), key=lambda kv: -kv[1]):
        print(f"{count:6}  {target}")
    print(f"{len(broken)} helper edges cross targets", file=sys.stderr)
    for user, helper in broken[:40]:
        print(f"   {user} -> {helper} ({plan[user]} -> {plan[helper]})", file=sys.stderr)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
