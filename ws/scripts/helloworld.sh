export TESTNAME=hello_world_iccm
export TESTDIR=${CALIPTRA_WORKSPACE}/scratch/usr/${TESTNAME}
mkdir -p ${TESTDIR}
rm -rf ${TESTDIR}/*

make -C ${TESTDIR} -f ${CALIPTRA_ROOT}/tools/scripts/Makefile TESTNAME=${TESTNAME} debug=1 verilator