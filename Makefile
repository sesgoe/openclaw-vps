.PHONY: init fmt validate plan apply output

init:
	./scripts/tf.sh init

fmt:
	./scripts/tf.sh fmt

validate:
	./scripts/tf.sh validate

plan:
	./scripts/tf.sh plan

apply:
	./scripts/tf.sh apply

output:
	./scripts/tf.sh output

