#include "CaeSim.h"
#include "CaeIsa.h"
#include <stdio.h>

#define NUM_AEGS 34
#define PERS_NUM 4

#define AEG_MA1 0
#define AEG_MA2 1
#define AEG_MA3 2
#define AEG_CNT 3
#define AEG_SUM 4 

#define NUM_MCS 8
#define NUM_AEPIPES 16
#define NUM_FPS 63
#define MEM_REQ_SIZE 8

#define AEUIE 0
#undef DEBUG

void
CCaeIsa::InitPers()
{
    SetAegCnt(NUM_AEGS);
    WriteAeg(0, 0, 0);
    SetPersNum(PERS_NUM);
    // clear the sum registers
    for (int aeId = 0; aeId < 4; aeId++) {
	WriteAeg(aeId, AEG_SUM, 0);
    }
}

void
CCaeIsa::CaepInst(int aeId, int opcode, int immed, uint32 inst, uint64 scalar) // F7,0,20-3F
{
    switch (opcode) {
	// CAEP00 - M[a1] + M[a2] -> M[a3]
	case 0x20: {
	    printf("Emulated result");	
	    WriteAeg(aeId, 0, 12111);
	    break;
	}

	default:{
	    printf("Default case hit - opcode = %x\n", opcode);
	    for (int aeId = 0; aeId < CAE_AE_CNT; aeId += 1)
		SetException(aeId, AEUIE);
	}
    }
}

