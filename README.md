# spatial-epi
A collection of models and other bits and pieces for thinking through how to do spatial epidemic spread modelling.

## Distributed stochastic branching model
The model below is a reimplementation of the stochastic branching model described [here](https://www.tepunahamatatini.ac.nz/2020/04/09/a-stochastic-model-for-covid-19-spread-and-the-effects-of-alert-level-4-in-aotearoa-new-zealand/), insofar as is possible given the limitations of that description and lack of access to detailed New Zealand cases and arrivals data prior to lockdown.

The major difference from that work is that the branching model of infectious spread is localised to regions (in this case District Healh Boards) so that reinfection of previously controlled areas might occur in the absence of strong controls on inter-regional travel.
+ [`nz-dhb-branching-beta.0.4-logging.nlogo`](http://southosullivan.com/misc/nz-dhb-branching-beta.0.4.html)

## Distributed SEIR models
These models have localised [SEIR models](https://en.wikipedia.org/wiki/Compartmental_models_in_epidemiology). More specifically these have been coded to match most of the parameters reported for the [Te Pūnaha Matatini SEIR model for COVID-19 in New Zealand, as described here](https://www.tepunahamatatini.ac.nz/2020/03/26/suppression-and-mitigation-strategies-for-control-of-covid-19-in-new-zealand/), although results are unlikely to match exactly given entirely different platform used (and the rapidly evolving situation).

The major change from the TPM model is that compartment model runs in individual regions (called 'locales' in the model) linked by a network of connections that mean that depending on travel restrictions that might be imposed or not, disease may reemerge in locales previously cleared. A focal interest is in how different sized regionalisation might allow quarantine levels to be relaxed more or less quickly without compromising measures of success in controlling the epidemic.
+ [`distributed-seir-08.nlogo`](http://southosullivan.com/misc/distributed-seir-08-web.html) adds logging of all locales data at every time step (the linked web version has no file logging)

A version that can also be initialised with NZ DHB data:
+ [`nz-dhb-seir-08.nlogo`](http://southosullivan.com/misc/nz-dhb-seir-08-web.html) adds logging reading of spatial data from input GUI elements (done this way to permit same in web version)

And with NZ Territorial Authority data:
+ [`nz-ta-seir-08.nlogo`](http://southosullivan.com/misc/nz-ta-seir-08-web.html) adds logging reading of spatial data from input GUI elements (done this way to permit same in web version)

A preliminary result from this model is shown below, suggesting that similar levels of control over spread can be maintained while returning more regions to low or no quarantine restrictions if quarantine is managed more locally (i.e. using a finer grained regional map.)
#### Population in different lockdown levels by number of locales
<img src='population-in-different-alert-levels-by-num-locales.png' width=800>

#### Epidemic results by number of locales
<img src='pandemic-time-series-by-num-locales.png' width=800>

## Earlier versions of the distributed SEIR model
These have been 'frozen' for reference purposes and because 'releases' aren't really appropriate to this project. Brief details as follows, with links to web version where available:
+ [`distributed-seir-07.nlogo`](http://southosullivan.com/misc/distributed-seir-07.html) as previous but with automatic control of lockdown levels according to a variety of strategies
+ [`distributed-seir-06.nlogo`](http://southosullivan.com/misc/distributed-seir-06.html) as previous but with correction to locale sizes to match total population more closely
+ `distributed-seir-05.nlogo` fixed lockdown levels and testing added
+ `distributed-seir-04.nlogo` reverts back to the main sequence and allows for locales to vary in size and variance, under paramterisable control

Three even earlier versions have excessive mortality, which has been corrected in later models. The later models are more worth spending time with.
+ `distributed-seir-03.nlogo` is an attempt to enable the model to read in real health management zones. It works, but requires some idiosyncratic code for the file reading.
+ [`distributed-seir-02.nlogo`](http://southosullivan.com/misc/distributed-seir-02.html) has more spatially coherent connections among the same
+ [`distributed-seir.nlogo`](http://southosullivan.com/misc/distributed-seir.html) has random connections among a set of equal-sized locales

## Experiments
In particular a series of Netlogo models, as follows. Two (very) toy models exploring self isolation 'bubbles'
+ [`bubbles.nlogo`](http://southosullivan.com/misc/bubbles.html)
+ [`nested-bubbles.nlogo`](http://southosullivan.com/misc/nested-bubbles.html)

### Web versions
You can make a web version of any of these by uploading the `.nlogo' file to [http://netlogoweb.org/](http://netlogoweb.org/launch#Load). Some models include `file-` commands not supported by Netlogo Web and will not work.
