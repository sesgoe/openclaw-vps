.PHONY: init fmt validate plan apply output destroy deploy login login-callback bring-up

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

destroy:
	./scripts/tf.sh destroy

deploy:
	./scripts/deploy.sh

login:
	./scripts/login.sh

login-callback:
	@./scripts/login.sh callback '$(URL)'

bring-up:
	./scripts/bring-up.sh
