include $(dir $(DESIGN_CONFIG))/config.mk

#export FLOW_VARIANT = hier
export FLOW_VARIANT = hier_rtlmp
export SYNTH_HIERARCHICAL = 1
export MAX_UNGROUP_SIZE = 100
export RTLMP_FLOW = True

export FLOORPLAN_DEF = ./results/$(PLATFORM)/$(DESIGN_NAME)/$(FLOW_VARIANT)/2_2_floorplan_io.def

# RTL_MP Settings
export RTLMP_MAX_INST = 5000
export RTLMP_MIN_INST = 1000
export RTLMP_MAX_MACRO = 12
export RTLMP_MIN_MACRO = 4

export DIE_AREA    = 0 0 1610 1360
export CORE_AREA   = 5 5 1605 1355
export PLACE_PINS_ARGS = -exclude left:* -exclude right:* -exclude top:* -exclude bottom:0-300 -exclude bottom:1300-1600

export PLACE_DENSITY = .75
