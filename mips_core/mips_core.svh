`define DATA_WIDTH 32
`define ADDR_WIDTH 26
`define REG_NUM 32
`define REG_NUM_INDEX ($clog2(`REG_NUM))
`define PHYS_REG_NUM (`REG_NUM * 2)
`define PHYS_REG_NUM_INDEX ($clog2(`PHYS_REG_NUM))
`define INT_QUEUE_SIZE 8
`define INT_QUEUE_SIZE_INDEX ($clog2(`INT_QUEUE_SIZE))
`define LOAD_STORE_SIZE 4
`define LOAD_STORE_SIZE_INDEX ($clog2(`LOAD_STORE_SIZE))
`define MEM_QUEUE_SIZE (`LOAD_STORE_SIZE * 2)
`define MEM_QUEUE_SIZE_INDEX ($clog2(`MEM_QUEUE_SIZE))
`define ACTIVE_LIST_SIZE 64
`define ACTIVE_LIST_SIZE_INDEX ($clog2(`ACTIVE_LIST_SIZE))
`define BRANCH_NUM 16
`define BRANCH_NUM_INDEX ($clog2(`BRANCH_NUM))
`define ISSUE_SIZE 2
import mips_core_pkg::*;
