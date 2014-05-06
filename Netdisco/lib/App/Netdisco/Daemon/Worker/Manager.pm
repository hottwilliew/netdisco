package App::Netdisco::Daemon::Worker::Manager;

use Dancer qw/:moose :syntax :script/;

use Role::Tiny;
use namespace::clean;

with 'App::Netdisco::Daemon::JobQueue::'. setting('job_queue');
requires qw/jq_get jq_getlocal jq_lock/;

sub worker_begin {
  my $self = shift;
  my $wid = $self->wid;
  debug "entering Manager ($wid) worker_begin()";

  # requeue jobs locally
  debug "mgr ($wid): searching for jobs booked to this processing node";
  my @jobs = $self->jq_getlocal;

  if (scalar @jobs) {
      info sprintf "mgr (%s): found %s jobs booked to this processing node", $wid, scalar @jobs;
      $self->do('add_jobs', @jobs);
  }
}

sub worker_body {
  my $self = shift;
  my $wid = $self->wid;
  my $num_slots = $self->do('num_workers')
    or return debug "mgr ($wid): this node has no workers... quitting manager";

  while (1) {
      debug "mgr ($wid): getting potential jobs for $num_slots workers";

      # get some pending jobs
      # TODO also check for stale jobs in Netdisco DB
      foreach my $job ( $self->jq_get($num_slots) ) {

          # check for available local capacity
          my $job_type = setting('job_types')->{$job->action};
          next unless $job_type and $self->do('capacity_for', $job_type);
          debug sprintf "mgr (%s): processing node has capacity for job %s (%s)",
            $wid, $job->id, $job->action;

          # mark job as running
          next unless $self->jq_lock($job);
          info sprintf "mgr (%s): job %s booked out for this processing node",
            $wid, $job->id;

          # copy job to local queue
          $self->do('add_jobs', $job);
      }

      debug "mgr ($wid): sleeping now...";
      sleep( setting('workers')->{sleep_time} || 2 );
  }
}

1;
