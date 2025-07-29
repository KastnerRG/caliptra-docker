export TESTNAME=smoke_test_sha256
export TESTDIR=${CALIPTRA_WORKSPACE}/scratch-vcs/usr/${TESTNAME}
mkdir -p ${TESTDIR}
rm -rf ${TESTDIR}/*

make -C ${TESTDIR} -f ${CALIPTRA_ROOT}/tools/scripts/Makefile TESTNAME=${TESTNAME} debug=1 vcs | tee ./${TESTNAME}_vcs.log