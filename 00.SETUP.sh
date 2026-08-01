#
# Adagio SETUP
#

#
# First install nextflow
#

cd bin
export NXF_VER=25.10.4
curl -s https://get.nextflow.io | bash
cd ..

#
# Reminder to run wgsTriage
#

cat <<END_REMINDER


=========================================================================

    REMINDER: Do not forget to run wgsTriage

        https://github.com/soccin/wgsTriage

        git clonesub git@github.com:soccin/wgsTriage.git

=========================================================================


END_REMINDER
