From: gongy@mskcc.org 
Subject: TEMPO WGS roadmap
Date: 2025-02-03

Hi, Dr Socci and John,

I have a solid working version of the new nf-core module compliant and faster alignment workflow of TEMPO and would like have you try on the WGS data you have problem with.

--------------------------------------------------------------------------
I initialized the nf-core compliant convertion of TEMPO with this branch, and this should be your baseline of the code comparison of the existing TEMPO develop branch, which is what we have being using for a long time now. No meaningful changes in this branch since this is purely for converting TEMPO devlop branch to be nf-core tools compliant.
https://github.com/mskcc/tempo/tree/nf-core/initiate

--------------------------------------------------------------------------
Actual changes happens next:
I have implemented a split-interval BQSR strategy as Sarek did in their new version, which significantly reduced the time cost for BQSR. For whole exomes, we have seen the entire BQSR steps (5 steps in total) took about 5 mins compare to 50+ minis using the previous BQSR steps we used in TEMPO (2 steps in total). You should be able to see the same scale of improvement in your WGS samples with sufficient resources given. We would be very intested to see the real time test from you. The actual changes I made this happen can be found here:
https://github.com/mskcc/tempo/compare/nf-core/initiate...nf-core/markdup_bqsr

==========================================================================
From: gongy@mskcc.org 
Subject: TEMPO WGS roadmap
Date: 2025-10-03

Hi, Nick,

What John said is right. 

And some details:

“@Dr Socci you could start using https://github.com/mskcc/tempo/tree/nf-core/markdup_bqsr to test for the most mature implementation, which will improve BQSR significantly. 
You could also test using https://github.com/mskcc/tempo/tree/nf-core/SetNmMdAndUqTags to see where we stand for MarkDup Spark.”

==========================================================================
From: gongy@mskcc.org 
Subject: TEMPO WGS roadmap
Date: 2025-04-08

Hi Nick,

Thanks for sharing it with us. Could you point me to the trace.txt file nextflow generates for every run? We are interested to see the time and resource it used.

Also, since you mentioned about space issue, we recently discovered a general nf-core module issue which cause bqsr work directory to use extensive amount of spaces. We have solved that issue together with nf-core. It likely impacts your run so I would recommend you to run nf-core update modules command to update bqsr modules we used in TEMPO. Please see details in the link below.

https://github.com/nf-core/modules/issues/7792

Next, for Delly, we do have a branch for it and it’s really just a version bump in the container. The actual command didn’t change at all. You can simply pull the new changes here.

https://github.com/mskcc/tempo/compare/develop...feature/upgrade_delly_v126?expand=1

For Manta, there is a newer version available and TEMPO is behind on updating to it. The release note did mention about performance improvement though. If you are interested you can try it out. We will eventually update it sometime in the future too.

NDS Notes:

Delly commit: 
f498c1ae Merge pull request #1 from mskcc/feature/upgrade_delly_v126 [GitHub]

==========================================================================
From: gongy@mskcc.org 
Subject: TEMPO WGS roadmap
Date: 2025-04-08

You can just update the bqsr module: (You might need to install nf-core tools https://nf-co.re/docs/nf-core-tools/installation)
`$ nf-core modules update gatk4/applybqsr`
https://nf-co.re/docs/nf-core-tools/modules/update

And SVaba is updated too:
https://github.com/mskcc/tempo/pull/1018/files
