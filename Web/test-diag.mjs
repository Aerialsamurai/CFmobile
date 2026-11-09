import { parseDiagnostics, parseRuntimeFault } from './src/diagnostics.js';
const s = `main.cpp:1:21: error: use of undeclared identifier 'y'
main.cpp:1:32: error: expected ';' after return statement
main.cpp:5:9: warning: implicit conversion loses integer precision: 'long long' to 'int' [-Wshorten-64-to-32]
main.cpp:6:9: warning: unused variable 'z' [-Wunused-variable]
main.cpp:7:3: warning: comparison of integers of different signs: 'int' and 'unsigned long' [-Wsign-compare]
main.cpp:9:7: error: no viable overloaded '>>'
main.cpp:9:7: error: use of undeclared identifier 'cnt'; did you mean 'count'?`;
console.log(parseDiagnostics(s));
console.log(parseRuntimeFault({stderr:'\x01UB|4|9|mul\n'}), parseRuntimeFault({timedOut:true}), parseRuntimeFault({crashed:'unreachable',stderr:''}));
