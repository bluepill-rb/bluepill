Bluepill.watch do
  start_command "start_process -P file.pid"
  stop_command "stop_process -P file.pid"
  pid_file 'file.pid'
  
  checks do |checks|
    checks.mem_usage :every => 15.minutes,
                  :below => 250.megabytes,
                  :fires => :restart
                  
    checks.cpu_usage  :every 10.seconds,
                :below => 50.percent,
                :fires => :restart
                
    checks.custom_method  :custom_params => :to_be_sent_to_the_custom_condition,
                          :fires => [:stop, :custom_event, :start]
                          
    checks.deadly_condition :every => 20.seconds,
                            :fires => :stop
  end
 
  handles(:restart) do |process|
    # process has pid
    process.transition :down
    process.transition :up
    run "some commands -P #{process.pid}"
  end
end