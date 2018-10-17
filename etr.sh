#!/bin/sh

erl -noshell -s etr start $@ -s init stop
