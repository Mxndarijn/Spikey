# Battle bot calibration (2026-11-17)

fastsim-rs battlebot-calibrate --seeds 60 --cap 14400 --jobs 2. 'beatsN': the share of rounds the bot wins against a player who scores N.

## Ladder 1 (the five measured tiers plus three between: too strong, levels 3-8 at the cap)
```
level  median  p25  p75  capped  beats10  beats20  beats30  beats45  beats60  beats80  beats120  beats180  beats250  beats400
    1      41   25   56       0      92%      88%      65%      42%      18%      12%       5%       0%       0%       0%
    2      46   33   69       2      95%      90%      78%      57%      38%      22%      15%       0%       0%       0%
    3     131   59  150      15     100%      95%      88%      78%      72%      62%      60%       0%       0%       0%
    4     151   93  154      24     100%     100%      98%      95%      85%      80%      72%       0%       0%       0%
    5     153  150  158      32     100%     100%     100%     100%      95%      92%      92%       0%       0%       0%
    6     153  150  158      36     100%     100%     100%     100%      98%      98%      98%       0%       0%       0%
    7     153  150  157      36     100%     100%      98%      98%      98%      95%      95%       0%       0%       0%
    8     154  150  158      40     100%     100%     100%     100%     100%     100%     100%       0%       0%       0%
```

## Ladder 2 (kept): a person's thumb at the bottom
```
level  median  p25  p75  capped  beats10  beats20  beats30  beats45  beats60  beats80  beats120  beats180  beats250  beats400
    1      20   12   29       0      77%      48%      23%       7%       0%       0%       0%       0%       0%       0%
    2      23   10   33       0      73%      53%      32%      10%       2%       0%       0%       0%       0%       0%
    3      32   20   48       0      92%      73%      55%      27%      15%       5%       3%       0%       0%       0%
    4      38   24   56       0      95%      85%      60%      38%      22%      13%       3%       0%       0%       0%
    5      54   32   81       4      97%      88%      77%      62%      43%      27%      15%       0%       0%       0%
    6     129   59  150      20     100%      95%      90%      82%      73%      62%      58%       0%       0%       0%
    7     157  150  159      52     100%     100%     100%     100%      97%      95%      95%       0%       0%       0%
    8     157  151  159      60     100%     100%     100%     100%     100%     100%     100%       0%       0%       0%
```

## Ladder 3 (level 1 at 3.6 ticks: median 19, no weaker than ladder 2's level 1)
```
level  median  p25  p75  capped  beats10  beats20  beats30  beats45  beats60  beats80  beats120  beats180  beats250  beats400
    1      19   11   27       0      77%      48%      13%       0%       0%       0%       0%       0%       0%       0%
    2      20   12   29       0      77%      48%      23%       7%       0%       0%       0%       0%       0%       0%
    3      32   20   48       0      92%      73%      55%      27%      15%       5%       3%       0%       0%       0%
    4      38   24   56       0      95%      85%      60%      38%      22%      13%       3%       0%       0%       0%
    5      54   32   81       4      97%      88%      77%      62%      43%      27%      15%       0%       0%       0%
    6     129   59  150      20     100%      95%      90%      82%      73%      62%      58%       0%       0%       0%
    7     157  150  159      52     100%     100%     100%     100%      97%      95%      95%       0%       0%       0%
    8     157  151  159      60     100%     100%     100%     100%     100%     100%     100%       0%       0%       0%
```
