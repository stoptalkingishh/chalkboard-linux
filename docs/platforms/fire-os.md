# Fire OS plan

Fire tablets will use supported child profiles and Amazon Parent Dashboard as
the baseline. Optional ADB helpers may reduce unwanted applications or apply
repeatable settings, but they must be reversible and scoped to tested Fire OS
versions.

The supported Amazon Appstore version of Khan Academy Kids belongs in the Fire
tablet catalog. Duolingo ABC is officially available for Android through Google
Play, but Amazon Appstore availability must be confirmed on the target Fire OS
device before it is included; sideloading is not the default plan.

The implementation must not assume that packages disabled on one tablet are
safe to disable on another. Device model, Fire OS version, child profile type,
and recovery method must be recorded before automation is applied.
