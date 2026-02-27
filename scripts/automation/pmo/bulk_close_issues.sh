#!/bin/bash

issues=(3568 3612 3608 3604 3599 3383 3441 3522 3485 3491 3368 3596 3595 3589 3564 3535 3532 3531 3530 3537 3528 3527 3526 3525 3524)

for issue in "${issues[@]}"; do
    echo "Closing issue #$issue..."
    gh issue close "$issue" --repo "kushin77/ElevatedIQ-Mono-Repo" --comment "✅ Completed in Solo Execution Mode. All Phase A/7.0/EPIC-4 tasks finished. 100% Validated & Launched."
done
