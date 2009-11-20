#--
# Copyright (c) 2005-2009, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++


require 'rufus/scheduler'
require 'ruote/engine/context'


module Ruote

  #
  # Ruote encapsulates a pointer to a flow expression (fei) and a method
  # name in an instance of FexpSchedulable. When the scheduler determines
  # the time has come, the flow expression is retrieved and the method is
  # called.
  #
  class FexpSchedulable

    def initialize (fei, m)

      @fei = fei
      @method = m
    end

    def call (rufus_job)

      context = rufus_job.scheduler.options[:context]

      opts = { :fei => @fei, :scheduler => true }

      if @method == :reply

        fexp = context[:s_expression_storage][@fei]

        unless fexp
          p [ :call_scheduled_reply, :missing, @fei.to_s ]
          # something has gone wrong, unschedule self
          rufus_job.unschedule
          return
        end

        opts[:workitem] = fexp.applied_workitem

      elsif @method == :cancel

        opts[:flavour] = :timeout
      end

      context[:s_workqueue].emit!(:expressions, @method, opts)
    end
  end

  #
  # Keeping track of a service (found in the ruote engine context) that
  # has to be scheduled from time to time (for example, a listener).
  #
  # Only the name of the 'service' is kept (for easy serialization).
  #
  # The service is only expected to respond to #call (with one argument,
  # the rufus-scheduler job itself)
  #
  class ServiceSchedulable

    def initialize (service_name)

      @service_name = service_name
    end

    def call (rufus_job)

      context = rufus_job.scheduler.options[:context]

      context[@service_name].call(rufus_job)
    end
  end

  #
  # Wrapping a rufus-scheduler instance, for handling all the time-related
  # things in ruote ('wait', timeouts, ...)
  #
  class Scheduler

    include EngineContext

    raise(
      "please upgrade to rufus-scheduler >= 2.0.2"
    ) if [ '2.0.2', Rufus::Scheduler::VERSION ].sort.first != '2.0.2'

    def context= (c)

      @context = c

      @scheduler = Rufus::Scheduler.start_new(:context => @context)

      reload
        # reloading (rescheduling) could be necessary if the expression
        # storage is persistent
    end

    def shutdown

      @scheduler.stop
    end

    def at (t, *args)

      @scheduler.at(t, :schedulable => new_schedulable(args))
    end

    def in (t, *args)

      @scheduler.in(t, :schedulable => new_schedulable(args))
    end

    def every (freq, *args)

      @scheduler.every(freq, :schedulable => new_schedulable(args))
    end

    def cron (cron_string, *args)

      @scheduler.cron(cron_string, :schedulable => new_schedulable(args))
    end

    def unschedule (job_id)

      @scheduler.unschedule(job_id)
    end

    def jobs

      @scheduler.all_jobs
    end

    # Clears all jobs. Mostly used by the test framework.
    #
    def purge!

      @scheduler.all_jobs { |j| @scheduler.unschedule(j.job_id) }
    end

    protected

    # Should be called only when the scheduler persistent data got lost.
    # Reloads all expressions and reschedules them (timeout, cron, whateever)
    # if necessary.
    #
    def reload

      expstorage.find_expressions.each do |exp|
        exp.reschedule_timeout
        exp.reschedule if exp.respond_to?(:reschedule)
      end
    end

    def new_schedulable (args)

      if args.size > 1
        FexpSchedulable.new(args[0], args[1]) # fei, method
      else
        ServiceSchedulable.new(args[0]) # service_name
      end
    end
  end
end
