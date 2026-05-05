smoke:
	./tools/sim_manager.py -s xsim -t tests/smoke.tlist 

decodes:
	python3 open-decode-tables/src/main.py -t open-decode-tables/tables/rv32im.yaml -o rtl/idu

clean:
	rm -rf obj_dir
	rm -rf x*
	rm -rf *.log
	rm -rf *.vcd
	rm -rf *.zip
	rm -rf *.wdb
	rm -rf .Xil
	rm -rf work

SIM ?= verilator
TEST_DIR = tools/sim_manager.py

.PHONY: test

sim:
	@if [ -z "$(T)" ]; then \
		echo "Error: Specify a program. Example: make sim T=basic_lui"; \
	else \
		case "$(T)" in \
			*.*) FINAL_T="$(T)" ;; \
			*)   FINAL_T="asm.$(T)" ;; \
		esac; \
		python3 $(TEST_DIR) -n $$FINAL_T -s $(SIM); \
	fi