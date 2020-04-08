;;
;; Model for exploring spatial epidemiology of COVID-19
;; from the perspective of regionalised control by 'alert levels'
;; governing local R0
;;
;; One of a series of models, see https://github.com/DOSull/spatial-epi
;;
;; David O'Sullivan
;; david.osullivan@vuw.ac.nz
;;


;; localities where control is administered
breed [locales locale]
locales-own [
  pop-0              ;; intial population
  susceptible        ;; susceptible
  exposed            ;; exposed
  presymptomatic     ;; infected but not symptomatic
  infected           ;; infected and symptomatic
  recovered          ;; recovered
  dead               ;; dead

  untested
  tests
  tests-positive

  new-exposed
  new-presymptomatic
  new-infected
  new-recovered
  new-dead

  new-tests
  new-tests-positive

  alert-level        ;; local alert level which controls...
  my-alert-indicator ;; local level turtle indicator
  my-R0              ;; local R0 and
  my-trans-coeff     ;; local transmission rate

  name
]

;; visualization aid to show alert levels
breed [levels level]
levels-own [
  alert-level
  my-locale
]

;; connections to other locales
directed-link-breed [connections connection]
connections-own [
  w ;; inverse distance weighted _outward_ from each
  my-flow-rate
]


globals [
  n-icu
  cfr-tot

  R0-levels         ;; R0s associated with the alert levels
  flow-levels
  trigger-levels

  mean-R0           ;; pop weighted mean R0
  mean-trans-coeff  ;; pop weighted mean trans coeff

  total-exposed            ;; exposed
  total-presymptomatic     ;; infected but not symptomatic
  total-infected           ;; infected and symptomatic
  total-recovered          ;; recovered
  total-dead               ;; dead

  all-tests
  all-tests-positive

  total-new-exposed
  total-new-presymptomatic
  total-new-infected
  total-new-recovered
  total-new-dead

  all-new-tests
  all-new-tests-positive

  log-header-file-name
  log-file-name
  full-file-name
  date-time
  model-name
  labels-on?

  alert-level-changes

  size-adjust
]

to setup
  clear-all

  ask patches [set pcolor cyan + 1]

  set-default-shape locales "circle"
  set-default-shape levels "square 3"
  set-default-shape connections "myshape"


  if use-seed? [random-seed seed]

  set R0-levels read-from-string alert-levels-R0
  set flow-levels read-from-string alert-levels-flow
  set trigger-levels read-from-string alert-level-triggers

  ifelse initialise-from-nz-data? [
    initialise-locales-from-string dhbs
    initialise-connections-from-string connectivity
  ]
  [
    initialise-locales-parametrically
    initialise-connections-parametrically
  ]
  setup-levels

  ;; initial exposures
  ifelse uniform-by-pop? [
    uniform-expose-by-population initial-infected
  ]
  [
    repeat initial-infected [
      ask one-of locales [
        initial-infect
      ]
    ]
  ]
  set all-new-tests []
  set all-new-tests-positive []
  update-global-parameters

  set size-adjust 0.25 / sqrt (count locales / count patches)
  ask turtles [ set size size * size-adjust ]
;  jiggle
  ask connections [ set thickness thickness * size-adjust ]

  set labels-on? true
  redraw
  paint-land lime - 1 4

  reset-ticks
end

to-report replace [s a b]
  let i position a s
  report replace-item i s b
end

;; susceptible weighted infection so
;; that higher population locales are more
;; likely to receive exposures
to uniform-expose-by-population [n]
  repeat n [
    ;; build cumulative total of susceptibles by locale
    ;; ordered from highest to lowest
    let susc reverse sort [susceptible] of locales
    let cum-susc cumulative-sum susc
    let total-susc last cum-susc

    ;; order locales similarly
    let ordered-locales reverse sort-on [susceptible] locales

    ;; pick a random number and use it to pick the corresponding locale
    let i random total-susc
    let idx length filter [ x -> x < i ] cum-susc
    ask item idx ordered-locales [
      initial-infect
    ]
  ]
end


to initial-infect
  set susceptible susceptible - 1

  let choose one-of (list 1 2 3)
  if choose = 1 [
    set exposed exposed + 1
    stop
  ]
  if choose = 2 [
    set presymptomatic presymptomatic + 1
    stop
  ]
  set infected infected + 1
end

to-report cumulative-sum [lst]
  let starter sublist lst 0 1
  report reduce [ [a b] -> lput (last a + b) a] (fput starter but-first lst)
end

to update-global-parameters
  set mean-R0 sum [my-R0 * susceptible] of locales / sum [susceptible] of locales
  set mean-trans-coeff sum [my-trans-coeff * susceptible] of locales / sum [susceptible] of locales

  set total-exposed sum [exposed] of locales
  set total-presymptomatic sum [presymptomatic] of locales
  set total-infected sum [infected] of locales
  set total-recovered sum [recovered] of locales
  set total-dead sum [dead] of locales

  set total-new-exposed sum [new-exposed] of locales
  set total-new-presymptomatic sum [new-presymptomatic] of locales
  set total-new-infected sum [new-infected] of locales
  set total-new-recovered sum [new-recovered] of locales
  set total-new-dead sum [new-dead] of locales

  set all-tests sum [tests] of locales
  set all-tests-positive sum [tests-positive] of locales
  set all-new-tests fput (sum [first new-tests] of locales) all-new-tests
  set all-new-tests-positive fput (sum [first new-tests-positive] of locales) all-new-tests-positive

  set n-icu total-infected * p-icu
  set cfr-tot cfr-0
  if n-icu > icu-cap [
    set cfr-tot (cfr-0 * icu-cap + (n-icu - icu-cap) * cfr-1) / n-icu
  ]
end


;; -------------------------
;; Main
;; -------------------------
to go
  if ((total-infected + total-presymptomatic + total-exposed) = 0 and ticks > 0) [
    update-global-parameters
    update-plots
    tick
    stop
  ]
  update-testing-results
  if ticks >= start-lifting-quarantine and (ticks - start-lifting-quarantine) mod time-horizon = 0 [
    change-alert-levels
  ]
  update-global-parameters

  ask locales [
    spread
  ]
  redraw

  tick
end


to change-alert-levels
  if alert-policy = "static" [ stop ]

  if alert-policy = "local-random" [
    ask locales [
      let alert-level-change one-of (list -1 0 1)
      let new-level alert-level + alert-level-change
      set-transmission-parameters clamp new-level 0 4
      set alert-level-changes alert-level-changes + 1
    ]
    enact-new-levels
    stop
  ]

  if alert-policy = "local" [
    ask locales [
      let recent-new-tests recent-total new-tests
      if recent-new-tests > 0 [
        let local-rate recent-total new-tests-positive / recent-new-tests
        let a get-new-alert-level local-rate
        if a != alert-level [
          set alert-level-changes alert-level-changes + 1
        ]
        ifelse a < alert-level [
          set alert-level alert-level - 1
        ]
        [
          set alert-level a
        ]
      ]
      set-transmission-parameters alert-level
    ]
    enact-new-levels
    stop
  ]

  if alert-policy = "global" [
    let recent-new-tests recent-total all-new-tests
    if recent-new-tests > 0 [
      let global-rate recent-total all-new-tests-positive / recent-new-tests
      let a get-new-alert-level global-rate
      if a != first [alert-level] of locales [
        set alert-level-changes alert-level-changes + 1
      ]
      ask locales [
        ifelse a < alert-level [
          set alert-level alert-level - 1
        ]
        [
          set alert-level a
        ]
        set-transmission-parameters alert-level
      ]
    ]
    enact-new-levels
    stop
  ]
end

to-report recent-total [lst]
  report sum sublist lst 0 time-horizon
end

to-report get-new-alert-level [r]
  report length filter [x -> r > x] trigger-levels
end

to-report clamp [x mn mx]
  report max (list mn min (list mx x))
end

to enact-new-levels
  ask levels [
    set alert-level [alert-level] of my-locale
    draw-level
  ]
  ask connections [
    set my-flow-rate min [item alert-level flow-levels] of both-ends
  ]
end


to set-transmission-parameters [a]
  set alert-level a
  set my-R0 item alert-level R0-levels
  set my-trans-coeff get-transmission-coeff my-R0
end

to-report get-transmission-coeff [R]
  report R / (relative-infectiousness-presymptomatic / presymptomatic-to-infected + 1 / infected-to-recovered)
end



to spread
  ;; calculate all the flows
  set new-exposed random-binomial susceptible (my-trans-coeff * (relative-infectiousness-presymptomatic * get-effective-presymptomatic + get-effective-infected) / (pop-0 - dead))
  set new-presymptomatic random-binomial exposed exposed-to-presymptomatic
  set new-infected random-binomial presymptomatic presymptomatic-to-infected

  let no-longer-infected random-binomial infected infected-to-recovered
  set new-recovered random-binomial no-longer-infected (1 - cfr-tot)
  set new-dead no-longer-infected - new-recovered

;  show word "new exposed " new-exposed
;  show word "new presymptomatic " new-presymptomatic
;  show word "new infected " new-infected
;  show word "no longer infected " no-longer-infected
;  show word "new recovered " new-recovered
;  show word "new dead " new-dead

  ;; update all the stocks
  expose new-exposed
  presym new-presymptomatic
  infect new-infected
  recover new-recovered
  kill new-dead
end

to update-testing-results
  ask locales [
    set new-tests-positive fput (random-binomial infected testing-rate-symptomatic) new-tests-positive

    let new-tests-pre random-binomial (presymptomatic + exposed) testing-rate-presymptomatic
    let new-tests-negative random-binomial susceptible testing-rate-general
    set new-tests fput (first new-tests-positive + new-tests-pre + new-tests-negative) new-tests

    set tests tests + first new-tests
    set tests-positive tests-positive + first new-tests-positive
  ]
end

to expose [n]
  ;show word "expose " n
  set susceptible susceptible - n
  set exposed exposed + n
end

to presym [n]
  ;show word "presym " n
  set exposed exposed - n
  set presymptomatic presymptomatic + n
end

to infect [n]
  ;show word "infect " n
  set presymptomatic presymptomatic - n
  set infected infected + n
end

to recover [n]
  ;show word "recover " n
  set infected infected - n
  set recovered recovered + n
end

to kill [n]
  ;show word "kill " n
  set infected infected - n
  set pop-0 pop-0 - n
  set dead dead + n
end

to-report get-effective-infected
  report infected + flow-rate * sum [my-flow-rate * w * [infected] of other-end] of my-in-connections
end

to-report get-effective-presymptomatic
  report presymptomatic + flow-rate * sum [my-flow-rate * w * [presymptomatic] of other-end] of my-in-connections
end

;; --------------------------------------------------------------
;; NOTE
;; using random-poisson approximation for efficiency when n large
;; --------------------------------------------------------------
to-report random-binomial [n p]
  if p = 0 [report 0]
  if p = 1 [report n]
  if n > 100 and p <= 0.25 [report random-poisson (n * p)]
  report length filter [x -> x < p] (n-values n [x -> random-float 1])
end


;; --------------------------------
;; initialisation stuff
;; --------------------------------
;; locales
to initialise-locales-parametrically
  let pop-mean population / num-locales
  let pop-var pop-sd-multiplier * pop-sd-multiplier * pop-mean * pop-mean

  let alpha (pop-mean * pop-mean / pop-var)
  let lambda (pop-mean / pop-var)

  create-locales num-locales [
    let xy random-xy-with-buffer 0.1
    setxy item 0 xy item 1 xy
    set pop-0 ceiling (random-gamma alpha lambda)
  ]
  let adjustment population / sum [pop-0] of locales
  ask locales [
    set pop-0 round (pop-0 * adjustment)
  ]
  initialise-locales
end

to-report random-xy-with-buffer [buffer]
  report (list rescale random-xcor (min-pxcor - 0.5) (max-pxcor + 0.5) buffer true
               rescale random-ycor (min-pycor - 0.5) (max-pycor + 0.5) buffer false)
end


to initialise-locales
  let mean-pop-0 mean [pop-0] of locales
  ask locales [
    set size (pop-0 / mean-pop-0) ^ (1 / 3)
    set susceptible pop-0
    set exposed 0
    set presymptomatic 0
    set infected 0
    set recovered 0
    set dead 0

    set untested 0
    set tests 0
    set tests-positive 0

    set new-exposed 0
    set new-presymptomatic 0
    set new-infected 0
    set new-recovered 0
    set new-dead 0

    set new-tests (list 0)
    set new-tests-positive (list 0)

    set-transmission-parameters init-alert-level
  ]
end


to initialise-locales-from-string [s]
  let locales-data but-first split-string s "\n"

  let xs map [x -> read-from-string item 2 split-string x " "] locales-data
  let ys map [y -> read-from-string item 3 split-string y " "] locales-data
  let min-x min xs    let max-x max xs
  let min-y min ys    let max-y max ys
  set xs map [x -> rescale x min-x max-x 0.1 true] xs
  set ys map [y -> rescale y min-y max-y 0.1 false] ys

  create-locales length locales-data

  (foreach locales-data sort locales xs ys [ [line loc x y] ->
    let parameters split-string line " "
    ask loc [
      set name item 1 parameters
      set label name
      set label-color black
      set pop-0 read-from-string item 4 parameters
      setxy x y
    ]
  ])
  initialise-locales
end

to-report rescale [z min-z max-z buffer x?]
  let new-range ifelse-value x? [(world-width - 1) * (1 - buffer)] [(world-height - 1) * (1 - buffer)]
  let new-min ifelse-value x? [(world-width - 1 - new-range) / 2] [(world-height - 1 - new-range) / 2]
  let new-z new-min + (z - min-z) / (max-z - min-z) * new-range
  report new-z
end


to setup-levels
  ask locales [
    let x nobody
    hatch 1 [
      set size size * 1.2
      set breed levels
      set my-locale myself
      set x self
      set label ""
    ]
    set my-alert-indicator x
  ]
end


;; their connections
to initialise-connections-parametrically
  ask locales [
    create-pair-of-connections self nearest-non-neighbour
  ]
  let num-links (6 * count locales)
  while [count connections < num-links] [
    ask one-of locales [
      create-pair-of-connections self nearest-non-neighbour
    ]
  ]
  reweight-connections
end

to-report nearest-non-neighbour
  report first sort-on [distance myself] (other locales with [not connection-neighbor? myself])
end


to initialise-connections-from-string [s]
  let edges but-first split-string s "\n"
  foreach edges [ edge ->
    let parameters split-string edge " "
    let v1 locale (read-from-string item 0 parameters)
    let v2 locale (read-from-string item 1 parameters)
    let weight read-from-string item 2 parameters
    ask v1 [
      create-connection-to v2 [
        initialise-connection weight
      ]
    ]
  ]
  reweight-connections
end


;; creates directed links between a and b in both directions
to create-pair-of-connections [a b]
  ask a [
    let d distance b
    create-connection-to b [initialise-connection d]
  ]
  ask b [
    let d distance a
    create-connection-to a [initialise-connection d]
  ]
end

to initialise-connection [d]
  set color [204 102 0 127]
  set w 1 / d
  set thickness w
end

to reweight-connections
  ask locales [
    let total-w sum [w] of my-out-connections
    let w-correction 1 / total-w
    let thickness-correction 1 / total-w
    ask my-out-connections [
      set w w * w-correction
      set thickness thickness * thickness-correction
    ]
  ]
end

;; ----------------------------
;; Drawing stuff
;; ----------------------------
to redraw
  ask locales [
    draw-locale
  ]
  ask levels [
    draw-level
  ]
end

to draw-locale
  set color scale-color red dead (cfr-0 * pop-0) 0
end

to toggle-labels
  set labels-on? not labels-on?
  ask locales [
    ifelse labels-on?
    [ set label name ]
    [ set label "" ]
  ]
end

to draw-level
  set alert-level [alert-level] of my-locale
  set color item alert-level (list pcolor lime yellow orange red)
end

to-report string-as-list [str]
  report n-values length str [i -> item i str]
end

to-report split-string [str sep]
  let words []
  let this-word ""
  foreach (string-as-list str) [ c ->
    ifelse c = sep
    [ set words sentence words this-word
      set this-word "" ]
    [ set this-word word this-word c ]
  ]
  ifelse this-word = ""
  [ report words ]
  [ report sentence words this-word ]
end



to paint-land [c n]
  let loc nobody
  let t nobody
  ask locales [
    set loc self
    ask patch-here [
      sprout 1 [
        set color c
        move-to loc
        set pcolor color
        set t self
      ]
    ]
    let targets sort-on [length-link] my-out-connections
    set targets sublist targets 0 min (list length targets n)
    foreach targets [ edge ->
      ask t [
        walk-edge self loc edge
      ]
    ]
    ask t [die]
  ]
end

to walk-edge [ttl loc edge]
  ask loc [
    let tgt [other-end] of edge
    ask ttl [
      face tgt
      let d distance tgt
      let ceiling-d ceiling d
      repeat ceiling-d [
        fd d / ceiling-d
        set pcolor color
      ]
    ]
  ]
end

to-report length-link
  let d 0
  ask one-of both-ends [
    set d distance [other-end] of myself
  ]
  report d
end


to-report join-list [lst sep]
  report reduce [ [a b] -> (word a sep b) ] lst
end
@#$#@#$#@
GRAPHICS-WINDOW
540
12
932
597
-1
-1
24.0
1
14
1
1
1
0
0
0
1
0
15
0
23
1
1
1
ticks
100.0

BUTTON
532
623
606
657
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
614
623
679
657
step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
684
624
748
658
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
348
63
522
96
num-locales
num-locales
20
200
100.0
10
1
NIL
HORIZONTAL

SLIDER
12
155
195
188
exposed-to-presymptomatic
exposed-to-presymptomatic
0
1
0.25
0.01
1
NIL
HORIZONTAL

SLIDER
13
196
194
229
presymptomatic-to-infected
presymptomatic-to-infected
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
12
236
195
269
infected-to-recovered
infected-to-recovered
0
1
0.1
0.01
1
NIL
HORIZONTAL

SLIDER
12
277
317
310
relative-infectiousness-presymptomatic
relative-infectiousness-presymptomatic
0
1
0.15
0.01
1
NIL
HORIZONTAL

MONITOR
86
26
213
71
mean-trans-coeff
mean-trans-coeff
5
1
11

SLIDER
14
483
239
516
testing-rate-symptomatic
testing-rate-symptomatic
0
1
0.25
0.01
1
NIL
HORIZONTAL

SLIDER
13
380
153
413
cfr-0
cfr-0
0
0.1
0.01
0.001
1
NIL
HORIZONTAL

SLIDER
159
380
306
413
cfr-1
cfr-1
0
0.2
0.02
0.001
1
NIL
HORIZONTAL

SLIDER
13
338
150
371
p-hosp
p-hosp
0
0.5
0.05
0.01
1
NIL
HORIZONTAL

SLIDER
11
419
153
452
p-icu
p-icu
0
p-hosp
0.0125
0.0001
1
NIL
HORIZONTAL

SLIDER
158
419
308
452
icu-cap
icu-cap
100
600
500.0
10
1
beds
HORIZONTAL

SLIDER
696
669
869
702
initial-infected
initial-infected
0
5000
2500.0
10
1
NIL
HORIZONTAL

PLOT
953
14
1298
289
totals
days
log (people + 1)
0.0
6.0
0.0
6.0
true
true
"" ""
PENS
"exposed" 1.0 0 -8431303 true "" "plot log (total-exposed + 1) 10"
"presymp" 1.0 0 -955883 true "" "plot log (total-presymptomatic + 1) 10"
"infected" 1.0 0 -2674135 true "" "plot log (total-infected + 1) 10"
"recovered" 1.0 0 -13840069 true "" "plot log (total-recovered + 1) 10"
"dead" 1.0 0 -16777216 true "" "plot log (total-dead + 1) 10"

SLIDER
540
710
713
743
seed
seed
0
100
30.0
1
1
NIL
HORIZONTAL

SLIDER
344
217
517
250
flow-rate
flow-rate
0
1
1.0
0.1
1
NIL
HORIZONTAL

SWITCH
542
672
681
705
use-seed?
use-seed?
1
1
-1000

SLIDER
348
26
521
59
population
population
100000
10000000
5000000.0
100000
1
NIL
HORIZONTAL

TEXTBOX
353
7
437
25
Population\n
12
0.0
1

TEXTBOX
7
6
91
24
Pandemic
12
0.0
1

TEXTBOX
10
297
94
315
Mortality
12
0.0
1

TEXTBOX
345
197
429
215
Connectivity
12
0.0
1

TEXTBOX
12
461
143
491
Control and testing
12
0.0
1

SLIDER
348
101
520
134
pop-sd-multiplier
pop-sd-multiplier
0.01
1.2
0.45
0.01
1
NIL
HORIZONTAL

MONITOR
263
24
343
69
total-pop
sum [pop-0] of locales
0
1
11

MONITOR
437
145
517
190
max-pop
max [pop-0] of locales
0
1
11

MONITOR
350
146
431
191
min-pop
min [pop-0] of locales
0
1
11

INPUTBOX
132
86
321
146
alert-levels-R0
[2.5 2.1 1.6 1.1 0.6]
1
0
String

MONITOR
7
26
79
71
mean-R0
mean-R0
3
1
11

SLIDER
348
287
521
320
init-alert-level
init-alert-level
0
4
4.0
1
1
NIL
HORIZONTAL

MONITOR
1302
110
1375
155
dead
total-dead
0
1
11

SWITCH
720
709
867
742
uniform-by-pop?
uniform-by-pop?
0
1
-1000

PLOT
952
294
1297
559
new-cases
days
number of people
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"exposed" 1.0 0 -6459832 true "" "plot total-new-exposed"
"presymp" 1.0 0 -955883 true "" "plot total-new-presymptomatic"
"infected" 1.0 0 -2674135 true "" "plot total-new-infected"
"recovered" 1.0 0 -13840069 true "" "plot total-new-recovered"
"dead" 1.0 0 -16777216 true "" "plot total-new-dead"

SLIDER
13
520
237
553
testing-rate-presymptomatic
testing-rate-presymptomatic
0
0.1
0.025
0.001
1
NIL
HORIZONTAL

SLIDER
12
559
236
592
testing-rate-general
testing-rate-general
0
0.002
5.0E-4
1
1
NIL
HORIZONTAL

PLOT
953
567
1301
855
testing
days
tests
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"tests-pos" 1.0 0 -7500403 true "" "plot all-tests-positive"
"new-tests" 1.0 0 -2674135 true "" "plot first all-new-tests"
"new-tests-pos" 1.0 0 -955883 true "" "plot first all-new-tests-positive"

INPUTBOX
367
519
523
579
alert-levels-flow
[1.0 0.5 0.25 0.1 0.05]
1
0
String

CHOOSER
367
327
520
372
alert-policy
alert-policy
"global" "local" "local-random" "static"
1

MONITOR
1302
14
1377
59
all-infected
total-infected + total-presymptomatic + total-exposed
0
1
11

MONITOR
1302
62
1375
107
recovered
total-recovered
0
1
11

INPUTBOX
316
377
523
437
alert-level-triggers
[0.0005 0.001 0.0025 0.005 1]
1
0
String

SLIDER
349
479
522
512
time-horizon
time-horizon
1
28
7.0
1
1
days
HORIZONTAL

SWITCH
701
753
872
786
log-all-locales?
log-all-locales?
1
1
-1000

SLIDER
322
440
524
473
start-lifting-quarantine
start-lifting-quarantine
0
56
28.0
7
1
days
HORIZONTAL

TEXTBOX
350
269
429
287
Alert levels
12
0.0
1

MONITOR
204
610
262
655
pop-lev-0
sum [pop-0] of locales with [alert-level = 0]
0
1
11

MONITOR
268
610
326
655
pop-lev-1
sum [pop-0] of locales with [alert-level = 1]
0
1
11

MONITOR
330
610
388
655
pop-lev-2
sum [pop-0] of locales with [alert-level = 2]
0
1
11

MONITOR
393
610
452
655
pop-lev-3
sum [pop-0] of locales with [alert-level = 3]
0
1
11

MONITOR
458
610
517
655
pop-lev-4
sum [pop-0] of locales with [alert-level = 4]
0
1
11

MONITOR
204
661
262
706
n-lev-0
count locales with [alert-level = 0]
0
1
11

MONITOR
268
661
326
706
n-lev-1
count locales with [alert-level = 1]
0
1
11

MONITOR
330
661
388
706
n-lev-2
count locales with [alert-level = 2]
0
1
11

MONITOR
393
661
452
706
n-lev-3
count locales with [alert-level = 3]
0
1
11

MONITOR
458
661
517
706
n-lev-4
count locales with [alert-level = 4]
0
1
11

INPUTBOX
699
790
884
850
log-folder
staging-area/retest-num-locales
1
0
String

SWITCH
10
719
196
752
initialise-from-nz-data?
initialise-from-nz-data?
0
1
-1000

INPUTBOX
6
756
382
850
dhbs
ID name x y pop\n35 Porirua.City 1754803 5444679 59100\n36 Upper.Hutt.City 1773987 5445388 46000\n37 Lower.Hutt.City 1760219 5434877 108700\n38 Wellington.City 1749100 5428463 210400\n39 Masterton.District 1824544 5463335 26800\n40 Carterton.District 1812507 5455416 9690\n41 South.Wairarapa.District 1800827 5443083 11100\n42 Tasman.District 1605286 5434837 54800\n0 Far.North.District 1661974 6104072 68500\n1 Whangarei.District 1721923 6044508 96000\n2 Kaipara.District 1696226 6013981 24100\n3 Thames-Coromandel.District 1837677 5900170 31500\n4 Hauraki.District 1839725 5862162 21000\n5 Waikato.District 1785683 5838225 79900\n6 Matamata-Piako.District 1835194 5825452 36000\n7 Hamilton.City 1800871 5815452 169500\n8 Waipa.District 1810124 5797080 56200\n9 Ōtorohanga.District 1790241 5774620 10500\n10 South.Waikato.District 1849099 5771898 25100\n23 Central.Hawke's.Bay.District 1904903 5568810 14850\n24 New.Plymouth.District 1695862 5676313 84400\n25 Stratford.District 1711134 5645373 9860\n26 South.Taranaki.District 1708671 5619311 28600\n27 Ruapehu.District 1802853 5669639 12750\n28 Whanganui.District 1775205 5577837 47300\n29 Rangitikei.District 1809324 5568325 15750\n30 Manawatu.District 1815966 5543552 31700\n31 Palmerston.North.City 1822162 5529590 88300\n32 Tararua.District 1854975 5533899 18650\n33 Horowhenua.District 1793597 5504781 35000\n34 Kapiti.Coast.District 1771493 5472047 56000\n11 Waitomo.District 1785591 5753009 9490\n12 Taupo.District 1861966 5710310 39300\n13 Western.Bay.of.Plenty.District 1879557 5826857 53900\n14 Tauranga.City 1881487 5825032 144700\n15 Rotorua.District 1885518 5774443 75100\n16 Whakatane.District 1946637 5786008 37100\n17 Kawerau.District 1924725 5778172 7490\n18 Ōpōtiki.District 1979259 5787601 9720\n19 Gisborne.District 2038766 5713797 49300\n20 Wairoa.District 1986371 5670970 8680\n21 Hastings.District 1930906 5605005 85000\n22 Napier.City 1936851 5621688 65000\n43 Nelson.City 1621899 5428781 52900\n44 Marlborough.District 1679129 5408151 49200\n45 Kaikoura.District 1655830 5305721 4110\n46 Buller.District 1490283 5372488 9840\n47 Grey.District 1456087 5299058 13750\n48 Westland.District 1419121 5250185 8960\n49 Hurunui.District 1587134 5244241 12950\n50 Waimakariri.District 1568013 5202021 62800\n51 Christchurch.City 1570759 5179833 385500\n52 Selwyn.District 1544814 5171648 65600\n53 Ashburton.District 1499844 5141411 34800\n54 Timaru.District 1460651 5088516 47900\n55 Mackenzie.District 1392391 5111453 5140\n56 Waimate.District 1446643 5045173 8080\n57 Waitaki.District 1435380 5003721 23200\n58 Central.Otago.District 1315931 4989515 23100\n59 Queenstown-Lakes.District 1271815 5018598 41700\n60 Dunedin.City 1405074 4917548 131700\n61 Clutha.District 1350001 4881249 18350\n62 Southland.District 1227217 4891543 32100\n63 Gore.District 1285924 4885546 12800\n64 Invercargill.City 1242280 4848618 56200\n65 Auckland 1757446 5921056 1642800\n
1
1
String

INPUTBOX
393
757
690
851
connectivity
ID1 ID2 cost\n0 1 0.5\n0 2 0.5\n0 65 1\n1 0 0.5\n1 2 0.5\n1 65 1\n2 0 0.5\n2 1 0.5\n2 65 0.5\n2 4 1\n2 5 1\n3 4 0.5\n3 5 1\n3 6 1\n3 13 1\n3 65 1\n4 3 0.5\n4 5 0.5\n4 6 0.5\n4 13 0.5\n4 65 0.5\n4 7 1\n4 8 1\n4 9 1\n4 10 1\n4 14 1\n4 15 1\n4 16 1\n4 2 1\n5 4 0.5\n5 6 0.5\n5 7 0.5\n5 8 0.5\n5 9 0.5\n5 65 0.5\n5 3 1\n5 13 1\n5 10 1\n5 11 1\n5 12 1\n5 2 1\n6 4 0.5\n6 5 0.5\n6 8 0.5\n6 10 0.5\n6 13 0.5\n6 3 1\n6 65 1\n6 7 1\n6 9 1\n6 12 1\n6 15 1\n6 14 1\n6 16 1\n7 5 0.5\n7 8 0.5\n7 4 1\n7 6 1\n7 9 1\n7 65 1\n7 10 1\n8 5 0.5\n8 6 0.5\n8 7 0.5\n8 9 0.5\n8 10 0.5\n8 4 1\n8 65 1\n8 13 1\n8 11 1\n8 12 1\n8 15 1\n9 5 0.5\n9 8 0.5\n9 10 0.5\n9 11 0.5\n9 12 0.5\n9 4 1\n9 6 1\n9 7 1\n9 65 1\n9 13 1\n9 15 1\n9 24 1\n9 27 1\n9 29 1\n9 16 1\n9 20 1\n9 21 1\n10 6 0.5\n10 8 0.5\n10 9 0.5\n10 12 0.5\n10 13 0.5\n10 15 0.5\n10 4 1\n10 5 1\n10 7 1\n10 11 1\n10 27 1\n10 29 1\n10 16 1\n10 20 1\n10 21 1\n10 14 1\n11 9 0.5\n11 24 0.5\n11 27 0.5\n11 12 0.5\n11 5 1\n11 8 1\n11 10 1\n11 25 1\n11 26 1\n11 28 1\n11 29 1\n11 15 1\n11 16 1\n11 20 1\n11 21 1\n12 9 0.5\n12 10 0.5\n12 27 0.5\n12 29 0.5\n12 11 0.5\n12 15 0.5\n12 16 0.5\n12 20 0.5\n12 21 0.5\n12 5 1\n12 8 1\n12 6 1\n12 13 1\n12 24 1\n12 25 1\n12 28 1\n12 23 1\n12 30 1\n12 17 1\n12 18 1\n12 19 1\n12 22 1\n13 4 0.5\n13 6 0.5\n13 10 0.5\n13 14 0.5\n13 15 0.5\n13 16 0.5\n13 3 1\n13 5 1\n13 65 1\n13 8 1\n13 9 1\n13 12 1\n13 17 1\n13 18 1\n13 19 1\n13 20 1\n13 21 1\n14 13 0.5\n14 4 1\n14 6 1\n14 10 1\n14 15 1\n14 16 1\n15 10 0.5\n15 12 0.5\n15 13 0.5\n15 16 0.5\n15 6 1\n15 8 1\n15 9 1\n15 27 1\n15 29 1\n15 11 1\n15 20 1\n15 21 1\n15 4 1\n15 14 1\n15 17 1\n15 18 1\n15 19 1\n16 12 0.5\n16 13 0.5\n16 15 0.5\n16 17 0.5\n16 18 0.5\n16 19 0.5\n16 20 0.5\n16 21 0.5\n16 9 1\n16 10 1\n16 27 1\n16 29 1\n16 11 1\n16 4 1\n16 6 1\n16 14 1\n16 23 1\n16 22 1\n17 16 0.5\n17 12 1\n17 13 1\n17 15 1\n17 18 1\n17 19 1\n17 20 1\n17 21 1\n18 16 0.5\n18 19 0.5\n18 12 1\n18 13 1\n18 15 1\n18 17 1\n18 20 1\n18 21 1\n19 16 0.5\n19 18 0.5\n19 20 0.5\n19 12 1\n19 13 1\n19 15 1\n19 17 1\n19 21 1\n20 12 0.5\n20 16 0.5\n20 19 0.5\n20 21 0.5\n20 9 1\n20 10 1\n20 27 1\n20 29 1\n20 11 1\n20 15 1\n20 13 1\n20 17 1\n20 18 1\n20 23 1\n20 22 1\n21 23 0.5\n21 29 0.5\n21 12 0.5\n21 16 0.5\n21 20 0.5\n21 22 0.5\n21 30 1\n21 32 1\n21 27 1\n21 28 1\n21 9 1\n21 10 1\n21 11 1\n21 15 1\n21 13 1\n21 17 1\n21 18 1\n21 19 1\n22 21 0.5\n22 23 1\n22 29 1\n22 12 1\n22 16 1\n22 20 1\n23 29 0.5\n23 30 0.5\n23 32 0.5\n23 21 0.5\n23 27 1\n23 28 1\n23 12 1\n23 31 1\n23 33 1\n23 39 1\n23 16 1\n23 20 1\n23 22 1\n24 25 0.5\n24 26 0.5\n24 27 0.5\n24 11 0.5\n24 28 1\n24 29 1\n24 12 1\n24 9 1\n25 24 0.5\n25 26 0.5\n25 27 0.5\n25 28 0.5\n25 11 1\n25 29 1\n25 12 1\n26 24 0.5\n26 25 0.5\n26 28 0.5\n26 27 1\n26 11 1\n26 29 1\n27 24 0.5\n27 25 0.5\n27 28 0.5\n27 29 0.5\n27 11 0.5\n27 12 0.5\n27 26 1\n27 23 1\n27 30 1\n27 21 1\n27 9 1\n27 10 1\n27 15 1\n27 16 1\n27 20 1\n28 25 0.5\n28 26 0.5\n28 27 0.5\n28 29 0.5\n28 24 1\n28 11 1\n28 12 1\n28 23 1\n28 30 1\n28 21 1\n29 23 0.5\n29 27 0.5\n29 28 0.5\n29 30 0.5\n29 12 0.5\n29 21 0.5\n29 32 1\n29 24 1\n29 25 1\n29 11 1\n29 26 1\n29 31 1\n29 33 1\n29 9 1\n29 10 1\n29 15 1\n29 16 1\n29 20 1\n29 22 1\n30 23 0.5\n30 29 0.5\n30 31 0.5\n30 32 0.5\n30 33 0.5\n30 21 1\n30 27 1\n30 28 1\n30 12 1\n30 39 1\n30 40 1\n30 34 1\n31 30 0.5\n31 32 0.5\n31 33 0.5\n31 23 1\n31 29 1\n31 39 1\n31 40 1\n31 34 1\n32 39 0.5\n32 23 0.5\n32 30 0.5\n32 31 0.5\n32 33 0.5\n32 40 1\n32 29 1\n32 21 1\n32 34 1\n33 39 0.5\n33 40 0.5\n33 30 0.5\n33 31 0.5\n33 32 0.5\n33 34 0.5\n33 41 1\n33 23 1\n33 29 1\n33 35 1\n33 36 1\n34 35 0.5\n34 36 0.5\n34 40 0.5\n34 41 0.5\n34 33 0.5\n34 37 1\n34 38 1\n34 39 1\n34 30 1\n34 31 1\n34 32 1\n35 36 0.5\n35 37 0.5\n35 38 0.5\n35 34 0.5\n35 41 1\n35 44 1\n35 40 1\n35 33 1\n36 35 0.5\n36 37 0.5\n36 41 0.5\n36 34 0.5\n36 38 1\n36 40 1\n36 33 1\n37 35 0.5\n37 36 0.5\n37 38 0.5\n37 41 0.5\n37 34 1\n37 44 1\n37 40 1\n38 35 0.5\n38 37 0.5\n38 44 0.5\n38 36 1\n38 34 1\n38 41 1\n38 42 1\n38 43 1\n38 45 1\n38 49 1\n39 40 0.5\n39 32 0.5\n39 33 0.5\n39 41 1\n39 34 1\n39 23 1\n39 30 1\n39 31 1\n40 39 0.5\n40 41 0.5\n40 33 0.5\n40 34 0.5\n40 32 1\n40 36 1\n40 37 1\n40 30 1\n40 31 1\n40 35 1\n41 36 0.5\n41 37 0.5\n41 40 0.5\n41 34 0.5\n41 35 1\n41 38 1\n41 39 1\n41 33 1\n42 43 0.5\n42 44 0.5\n42 46 0.5\n42 49 0.5\n42 45 1\n42 38 1\n42 47 1\n42 48 1\n42 50 1\n42 52 1\n43 42 0.5\n43 44 0.5\n43 46 1\n43 49 1\n43 45 1\n43 38 1\n44 42 0.5\n44 43 0.5\n44 45 0.5\n44 49 0.5\n44 38 0.5\n44 46 1\n44 47 1\n44 48 1\n44 50 1\n44 52 1\n44 35 1\n44 37 1\n45 44 0.5\n45 49 0.5\n45 42 1\n45 43 1\n45 38 1\n45 46 1\n45 47 1\n45 48 1\n45 50 1\n45 52 1\n46 42 0.5\n46 47 0.5\n46 49 0.5\n46 43 1\n46 44 1\n46 48 1\n46 45 1\n46 50 1\n46 52 1\n47 46 0.5\n47 48 0.5\n47 49 0.5\n47 42 1\n47 52 1\n47 53 1\n47 55 1\n47 57 1\n47 59 1\n47 62 1\n47 44 1\n47 45 1\n47 50 1\n48 47 0.5\n48 49 0.5\n48 52 0.5\n48 53 0.5\n48 55 0.5\n48 57 0.5\n48 59 0.5\n48 62 0.5\n48 46 1\n48 42 1\n48 44 1\n48 45 1\n48 50 1\n48 51 1\n48 54 1\n48 56 1\n48 58 1\n48 60 1\n48 61 1\n48 63 1\n48 64 1\n49 42 0.5\n49 44 0.5\n49 45 0.5\n49 46 0.5\n49 47 0.5\n49 48 0.5\n49 50 0.5\n49 52 0.5\n49 43 1\n49 38 1\n49 53 1\n49 55 1\n49 57 1\n49 59 1\n49 62 1\n49 51 1\n50 49 0.5\n50 51 0.5\n50 52 0.5\n50 42 1\n50 44 1\n50 45 1\n50 46 1\n50 47 1\n50 48 1\n50 53 1\n51 50 0.5\n51 52 0.5\n51 49 1\n51 48 1\n51 53 1\n52 48 0.5\n52 49 0.5\n52 50 0.5\n52 51 0.5\n52 53 0.5\n52 47 1\n52 55 1\n52 57 1\n52 59 1\n52 62 1\n52 42 1\n52 44 1\n52 45 1\n52 46 1\n52 54 1\n53 48 0.5\n53 52 0.5\n53 54 0.5\n53 55 0.5\n53 47 1\n53 49 1\n53 57 1\n53 59 1\n53 62 1\n53 50 1\n53 51 1\n53 56 1\n54 53 0.5\n54 55 0.5\n54 56 0.5\n54 48 1\n54 52 1\n54 57 1\n55 48 0.5\n55 53 0.5\n55 54 0.5\n55 56 0.5\n55 57 0.5\n55 47 1\n55 49 1\n55 52 1\n55 59 1\n55 62 1\n55 58 1\n55 60 1\n56 54 0.5\n56 55 0.5\n56 57 0.5\n56 53 1\n56 48 1\n56 58 1\n56 59 1\n56 60 1\n57 48 0.5\n57 55 0.5\n57 56 0.5\n57 58 0.5\n57 59 0.5\n57 60 0.5\n57 47 1\n57 49 1\n57 52 1\n57 53 1\n57 62 1\n57 54 1\n57 61 1\n58 57 0.5\n58 59 0.5\n58 60 0.5\n58 61 0.5\n58 62 0.5\n58 48 1\n58 55 1\n58 56 1\n58 63 1\n58 64 1\n59 48 0.5\n59 57 0.5\n59 58 0.5\n59 62 0.5\n59 47 1\n59 49 1\n59 52 1\n59 53 1\n59 55 1\n59 56 1\n59 60 1\n59 61 1\n59 63 1\n59 64 1\n60 57 0.5\n60 58 0.5\n60 61 0.5\n60 48 1\n60 55 1\n60 56 1\n60 59 1\n60 62 1\n60 63 1\n61 58 0.5\n61 60 0.5\n61 62 0.5\n61 63 0.5\n61 57 1\n61 59 1\n61 48 1\n61 64 1\n62 48 0.5\n62 58 0.5\n62 59 0.5\n62 61 0.5\n62 63 0.5\n62 64 0.5\n62 47 1\n62 49 1\n62 52 1\n62 53 1\n62 55 1\n62 57 1\n62 60 1\n63 61 0.5\n63 62 0.5\n63 58 1\n63 60 1\n63 48 1\n63 59 1\n63 64 1\n64 62 0.5\n64 48 1\n64 58 1\n64 59 1\n64 61 1\n64 63 1\n65 2 0.5\n65 4 0.5\n65 5 0.5\n65 0 1\n65 1 1\n65 3 1\n65 6 1\n65 13 1\n65 7 1\n65 8 1\n65 9 1\n
1
1
String

MONITOR
99
611
193
656
alert-activity
alert-level-changes / count locales / ticks
4
1
11

BUTTON
204
714
360
749
toggle-connections
ask connections [set hidden? not hidden?]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
366
714
492
748
NIL
toggle-labels
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

square 3
false
0
Rectangle -7500403 false true 15 15 285 285
Rectangle -7500403 false true 0 0 300 300
Rectangle -7500403 false true 7 9 292 293

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="compare-locale-sizes-static" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="730"/>
    <metric>total-infected</metric>
    <metric>total-recovered</metric>
    <metric>total-dead</metric>
    <enumeratedValueSet variable="alert-policy">
      <value value="&quot;static&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-presymptomatic">
      <value value="0.025"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-general">
      <value value="5.0E-4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-alert-level">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-seed?">
      <value value="true"/>
    </enumeratedValueSet>
    <steppedValueSet variable="seed" first="1" step="1" last="30"/>
    <enumeratedValueSet variable="relative-infectiousness-presymptomatic">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p-icu">
      <value value="0.0125"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pop-sd-multiplier">
      <value value="0.45"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population">
      <value value="5000000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p-hosp">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="uniform-by-pop?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-exposed">
      <value value="500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="infected-to-recovered">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow-rate">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cfr-0">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exposed-to-presymptomatic">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-horizon">
      <value value="7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-levels-R0">
      <value value="&quot;[2.5 2.1 1.6 1.1 0.6]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-locales">
      <value value="20"/>
      <value value="50"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cfr-1">
      <value value="0.02"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-levels-flow">
      <value value="&quot;[1.0 0.5 0.25 0.1 0.05]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presymptomatic-to-infected">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-level-triggers">
      <value value="&quot;[0.0005 0.001 0.0025 0.005 1]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="icu-cap">
      <value value="500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-symptomatic">
      <value value="0.25"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="compare-locale-sizes-local" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="730"/>
    <metric>total-infected</metric>
    <metric>total-recovered</metric>
    <metric>total-dead</metric>
    <enumeratedValueSet variable="alert-policy">
      <value value="&quot;local&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-presymptomatic">
      <value value="0.025"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-general">
      <value value="5.0E-4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-alert-level">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-seed?">
      <value value="true"/>
    </enumeratedValueSet>
    <steppedValueSet variable="seed" first="1" step="1" last="30"/>
    <enumeratedValueSet variable="relative-infectiousness-presymptomatic">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p-icu">
      <value value="0.0125"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pop-sd-multiplier">
      <value value="0.45"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="population">
      <value value="5000000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p-hosp">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="uniform-by-pop?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-exposed">
      <value value="500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="infected-to-recovered">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow-rate">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cfr-0">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exposed-to-presymptomatic">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-horizon">
      <value value="7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-levels-R0">
      <value value="&quot;[2.5 2.1 1.6 1.1 0.6]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-locales">
      <value value="20"/>
      <value value="50"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cfr-1">
      <value value="0.02"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-levels-flow">
      <value value="&quot;[1.0 0.5 0.25 0.1 0.05]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presymptomatic-to-infected">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-level-triggers">
      <value value="&quot;[0.0005 0.001 0.0025 0.005 1]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="icu-cap">
      <value value="500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-symptomatic">
      <value value="0.25"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="locale-sizes-vs-lockdown-counts" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="730"/>
    <metric>count turtles</metric>
    <enumeratedValueSet variable="testing-rate-presymptomatic">
      <value value="0.025"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-general">
      <value value="5.0E-4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-seed?">
      <value value="true"/>
    </enumeratedValueSet>
    <steppedValueSet variable="seed" first="1" step="1" last="30"/>
    <enumeratedValueSet variable="population">
      <value value="5000000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="uniform-by-pop?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="infected-to-recovered">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow-rate">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cfr-0">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-horizon">
      <value value="7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exposed-to-presymptomatic">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cfr-1">
      <value value="0.02"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-levels-flow">
      <value value="&quot;[1.0 0.5 0.25 0.1 0.05]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="icu-cap">
      <value value="500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="start-lifting-quarantine">
      <value value="28"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="log-all-locales?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-infected">
      <value value="2500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-policy">
      <value value="&quot;local&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-alert-level">
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="relative-infectiousness-presymptomatic">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p-icu">
      <value value="0.0125"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pop-sd-multiplier">
      <value value="0.45"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p-hosp">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-levels-R0">
      <value value="&quot;[2.5 2.1 1.6 1.1 0.6]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-locales">
      <value value="20"/>
      <value value="50"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presymptomatic-to-infected">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-symptomatic">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-level-triggers">
      <value value="&quot;[0.0005 0.001 0.0025 0.005 1]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="log-folder">
      <value value="&quot;staging-area/retest-num-locales&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="locale-sizes-base-rates-under-static-lockdown-levels" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="730"/>
    <enumeratedValueSet variable="testing-rate-presymptomatic">
      <value value="0.025"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-general">
      <value value="5.0E-4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="use-seed?">
      <value value="true"/>
    </enumeratedValueSet>
    <steppedValueSet variable="seed" first="1" step="1" last="30"/>
    <enumeratedValueSet variable="population">
      <value value="5000000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="uniform-by-pop?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="infected-to-recovered">
      <value value="0.1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow-rate">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cfr-0">
      <value value="0.01"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="time-horizon">
      <value value="7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exposed-to-presymptomatic">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cfr-1">
      <value value="0.02"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-levels-flow">
      <value value="&quot;[1.0 0.5 0.25 0.1 0.05]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="icu-cap">
      <value value="500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="start-lifting-quarantine">
      <value value="28"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="log-all-locales?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-infected">
      <value value="2500"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-policy">
      <value value="&quot;static&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="init-alert-level" first="0" step="1" last="4"/>
    <enumeratedValueSet variable="relative-infectiousness-presymptomatic">
      <value value="0.15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p-icu">
      <value value="0.0125"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="pop-sd-multiplier">
      <value value="0.45"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="p-hosp">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-levels-R0">
      <value value="&quot;[2.5 2.1 1.6 1.1 0.6]&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-locales">
      <value value="20"/>
      <value value="50"/>
      <value value="100"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="presymptomatic-to-infected">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="testing-rate-symptomatic">
      <value value="0.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="alert-level-triggers">
      <value value="&quot;[0.0005 0.001 0.0025 0.005 1]&quot;"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

myshape
0.6
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 135 165 150 150
Line -7500403 true 165 165 150 150
@#$#@#$#@
0
@#$#@#$#@