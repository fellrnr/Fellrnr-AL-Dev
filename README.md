# Fellrnr's modified ActiveLook DataField 

This is a modification of the ActiveLook DataField, which they have kindly open sourced. 

# Repurpose top line
Instead of showing the time and battery charge, the top line is now used for the workout information. The data that is shown when the lap button is pressed is shown in the top line. This is most useful when doing a structured workout (see below).


# Intervals not Laps
I've added the configuration of the number of laps per interval, then shown the interval and recovery numbers rather than lap numbers. That's easier if you're doing large numbers of intervals. I've also replaced the time in the top left with the interval/recovery number. This approach is a simple counter, so 
- lap 0 is considered the warmup
- lap 1 is interval 1
- lap 2 is recovery 1
- lap 3 is interval 2
- lap 4 is recovery 2
- and so on

# Structured workouts
If you have a structured workout, that information is used on the lap messages. The messages then have the format
'[AR][nn][intensity][duration][type][notes]

- AR is active or recovery segements of a repeat, though I never got this to work on my Fenix 6x, and it always blank.
- nn is the interval counter, which is incremented each time the intensity is "Active" or "Interval"
- intensity is a one or two character code
  - Active=go
  - Rest=rest
  - Warmup=wu
  - Cooldown=cd
  - Recovery=rec
  - Interval=int
- Duration is the duration value
- Type is m=meters, s=seconds, p=lap press (there are lots of other codes I've not mapped.)
- Notes are the notes field from the workout truncated to the available screen space

# Other fields
I added stride length based on pace and cadence to the available fields. 

# Freeze time
The time the screen is frozen after a lap button press is now configurable (it was too long for very short intervals.)
