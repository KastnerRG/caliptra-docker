export TESTDIR=${CALIPTRA_WORKSPACE}/scratch-${SIMULATOR}/usr/${TESTNAME}
mkdir -p ${TESTDIR}
rm -rf ${TESTDIR}/*

make -C ${TESTDIR} -f ${CALIPTRA_ROOT}/tools/scripts/Makefile TESTNAME=${TESTNAME} debug=1 ${SIMULATOR} | tee ./${TESTNAME}_${SIMULATOR}.log