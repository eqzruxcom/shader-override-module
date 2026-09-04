# Runtime toggle policy

## Authoritative controls

- **Page Down** is the single master A/B toggle for every retained injected
  effect. Master off must execute the original game path.
- **Page Up** belongs only to the experiment currently under live evaluation.
  It must not control a previously accepted feature.
- Other historical effect A/B hotkeys remain disabled while this workflow is
  active.

## Required shader structure

During a live experiment, generated code uses nested control flow:

```text
if (master_enabled) {
    run_retained_injected_effects();
    if (experiment_enabled) {
        run_current_experiment();
    }
} else {
    run_original_game_path();
}
```

The experiment branch must be independently removable. It must not become a
dependency of the retained effect or the original path.

## Promotion rule

When the user accepts an experiment as working:

1. incorporate the accepted behavior into the retained master-controlled
   effect;
2. remove the Page Up key section;
3. remove the experiment global variable and shader-constant binding;
4. remove the experiment-only shader condition and dead diagnostic code;
5. reassemble/compile and verify the promoted shaders;
6. verify that Page Down alone switches between the complete retained effect
   and original game behavior.

Page Up is then free for the next experiment.

## Current live state

The material-ID 1 Cloud-clothing route was confirmed and its temporary
diagnostic was removed during promotion. The five retained contact-shadow
compute replacements are all under the Page Down master. Page Up currently has
no key section, global variable, INI binding, or shader-side parameter load.
Seven obsolete hunter/ownership probes remain disabled because standalone
replacements could bypass the master path.

Authoritative audit:
`artifacts/runtime-toggle-audits/20260901-094109-403/manifest.json` reports five
active shaders, five Page Down gates, and zero Page Up shaders. The promotion
rollback is
`artifacts/live-rollbacks/contact-baseline-promotion-20260901-094035-060`.

## Family-scale template invariant

The eventual universal template must apply this policy to the generated shader
family, not merely to one observed hash:

1. every emitted active replacement declares its original hash/stage header;
2. every retained injected branch consumes the single Page Down master;
3. every Page Up consumer is explicitly listed in the current experiment
   manifest, and the allowed list may be empty;
4. an unexpected active replacement, key section, constant binding, or
   shader-side experiment load fails generation/audit;
5. promotion removes experiment controls before the next family is generated.

This prevents one mistaken binding from being replicated into thousands of
regional or permutation shaders.
