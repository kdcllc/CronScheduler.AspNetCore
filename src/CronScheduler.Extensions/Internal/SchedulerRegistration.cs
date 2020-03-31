using System;
using System.Collections.Concurrent;
using System.Collections.Generic;

using Cronos;

using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CronScheduler.Extensions.Internal
{
    internal class SchedulerRegistration : ISchedulerRegistration
    {
        private readonly IOptionsMonitor<SchedulerOptions> _optionsMonitor;
        private readonly ILogger<SchedulerRegistration> _logger;
        private readonly ConcurrentDictionary<string, IScheduledJob> _jobs = new ConcurrentDictionary<string, IScheduledJob>();
        private readonly ConcurrentDictionary<string, SchedulerTaskWrapper> _wrappedJobs = new ConcurrentDictionary<string, SchedulerTaskWrapper>();

        public SchedulerRegistration(
            IOptionsMonitor<SchedulerOptions> optionsMonitor,
            IEnumerable<IScheduledJob> scheduledJobs,
            ILogger<SchedulerRegistration> logger)
        {
            _optionsMonitor = optionsMonitor ?? throw new ArgumentNullException(nameof(optionsMonitor));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));

            foreach (var job in scheduledJobs)
            {
                AddOrUpdate(job.Name, job);
            }

            _optionsMonitor.OnChange((o, n) =>
            {
                if (_jobs.TryGetValue(n, out var job)
                    && _wrappedJobs.ContainsKey(n))
                {
                    AddJob(n, job, o);
                }
            });
        }

        public IReadOnlyDictionary<string, SchedulerTaskWrapper> Jobs => _wrappedJobs;

        public bool AddOrUpdate(IScheduledJob job, SchedulerOptions options)
        {
            return AddOrUpdate(job.GetType().Name, job, options);
        }

        public bool AddOrUpdate(string jobName, IScheduledJob job, SchedulerOptions options)
        {
            return AddJob(jobName, job, options);
        }

        public bool AddOrUpdate(IScheduledJob job)
        {
            return AddOrUpdate(job.GetType().Name, job);
        }

        public bool AddOrUpdate(string jobName, IScheduledJob job)
        {
            var options = _optionsMonitor.Get(jobName);

            return AddJob(jobName, job, options);
        }

        public bool Remove(string jobName)
        {
            return _jobs.TryRemove(jobName, out var job)
                && _wrappedJobs.TryRemove(jobName, out var wrap);
        }

        private bool AddJob(string name, IScheduledJob job, SchedulerOptions options)
        {
            _jobs.AddOrUpdate(name, job, (n, j) => job);

            var wrapped = Create(name, job, options);

            if (wrapped != null)
            {
                _wrappedJobs.AddOrUpdate(name, wrapped, (n, v) => wrapped);

                return true;
            }

            return false;
        }

        private SchedulerTaskWrapper? Create(string jobName, IScheduledJob job, SchedulerOptions options)
        {
            var currentTimeUtc = DateTimeOffset.UtcNow;
            var timeZone = TimeZoneInfo.Local;

            if (string.IsNullOrEmpty(options.CronSchedule))
            {
                _logger.MissingCron(jobName, options.CronSchedule);

                return null;
            }

            if (!string.IsNullOrEmpty(options.CronTimeZone))
            {
                try
                {
                    timeZone = TimeZoneInfo.FindSystemTimeZoneById(options.CronTimeZone);
                }
                catch (Exception ex)
                {
                    _logger.TimeZoneParseFailure(jobName, options.CronTimeZone, ex);
                    timeZone = TimeZoneInfo.Local;
                }
            }

            _logger.TimeZone(jobName, timeZone.Id);

            CronExpression crontabSchedule;

            if (options.CronSchedule.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries).Length == 6)
            {
                crontabSchedule = CronExpression.Parse(options.CronSchedule, CronFormat.IncludeSeconds);
            }
            else
            {
                crontabSchedule = CronExpression.Parse(options.CronSchedule, CronFormat.Standard);
            }

            var nextRunTime = options.RunImmediately ? currentTimeUtc : crontabSchedule.GetNextOccurrence(currentTimeUtc, timeZone) !.Value;

            return new SchedulerTaskWrapper(crontabSchedule, job, nextRunTime, timeZone);
        }
    }
}
