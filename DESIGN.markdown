## Bluepill Design
Here are just some bullet points of the design. We'll add details later.

 * Each process monitors a single _application_, so you can have multiple bluepill processes on a system
 * Use rotational arrays for storing historical data for monitoring process conditions
 * Memo-ize output of _ps_ per tick as an optimization for applications with many processes
 * Use socket files to communicate between CLI and daemon
 * DSL is a separate layer, the core of the monitoring just uses regular initializers, etc. DSL is simply for ease of use and should not interfere with business logic
 * Sequentially process user issued commands so no weird race cases occur
 * Triggers are notified by the state machine on any process state transitions