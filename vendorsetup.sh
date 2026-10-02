# Minimal TWRP manifest may not include all AOSP defaults modules
# (e.g. tradefed_defaults). Tell soong to skip missing deps at parse time.
export ALLOW_MISSING_DEPENDENCIES=true
