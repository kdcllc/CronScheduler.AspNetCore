using System;
using System.Threading.Tasks;

using CronScheduler.Extensions.Internal;
using CronScheduler.Extensions.Scheduler;

using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;

namespace Microsoft.Extensions.DependencyInjection
{
    public class SchedulerBuilder
    {
        /// <summary>
        /// EventHanlder for Startup for Hosted Apps.
        /// </summary>
#pragma warning disable CA1051 // Do not declare visible instance fields
#pragma warning disable SA1401 // Fields should be private
        public EventHandler<UnobservedTaskExceptionEventArgs>? UnobservedTaskExceptionHandler;
#pragma warning restore SA1401 // Fields should be private
#pragma warning restore CA1051 // Do not declare visible instance fields

        public SchedulerBuilder(IServiceCollection services)
        {
            Services = services ?? throw new ArgumentNullException(nameof(services));
            Services.TryAddSingleton<ISchedulerRegistration, SchedulerRegistration>();
        }

        /// <summary>
        /// <see cref="IServiceCollection"/> for the DI.
        /// </summary>
        public IServiceCollection Services { get; }

        /// <summary>
        /// Adds Custom Named Job.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <param name="sectionName">The section for the job configurations.</param>
        /// <param name="namedJob">The name of the job.</param>
        /// <returns></returns>
        [Obsolete("This method will be depreciated in the next release.")]
        public IServiceCollection AddJob<TJob>(string sectionName = "SchedulerJobs", string? namedJob = null)
            where TJob : class, IScheduledJob
        {
            Services.AddSingleton<IScheduledJob, TJob>();

            var name = namedJob ?? typeof(TJob).Name;

            // named options used within the scheduler itself.
            Services.AddChangeTokenOptions<SchedulerOptions>($"{sectionName}:{typeof(TJob).Name}", name, _ => { });

            return Services;
        }

        /// <summary>
        /// Adds schedule job with factory.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <typeparam name="TJobOptions">The type of the options.</typeparam>
        /// <param name="factory">The factory to register the job with.</param>
        /// <param name="configure">The action to configure custom options.
        ///                         This will override the what is in <see cref="IConfiguration"/> providers.
        /// </param>
        /// <param name="sectionName">The section name for the configurations.</param>
        /// <param name="jobName">The name of the job.</param>
        /// <returns></returns>
        public IServiceCollection AddJob<TJob, TJobOptions>(
            Func<IServiceProvider, TJob> factory,
            Action<TJobOptions>? configure = default,
            string sectionName = "SchedulerJobs",
            string? jobName = default)
            where TJob : class, IScheduledJob
            where TJobOptions : SchedulerOptions, new()
        {
            Services.AddSingleton(typeof(IScheduledJob), factory);

            var name = jobName ?? typeof(TJob).Name;

            AddOptions(configure, sectionName, name);

            return Services;
        }

        public IServiceCollection AddJob<TJob>(
            Func<IServiceProvider, TJob> factory,
            Action<SchedulerOptions>? configure = default,
            string sectionName = "SchedulerJobs",
            string? jobName = default)
            where TJob : class, IScheduledJob
        {
            var name = jobName ?? typeof(TJob).Name;

            Services.AddSingleton(typeof(IScheduledJob), factory);

            Services
              .AddChangeTokenOptions<SchedulerOptions>(
              $"{sectionName}:{name}",
              name,
              o =>
              {
                  configure?.Invoke(o);
                  o.JobName = name;
              });

            return Services;
        }

        /// <summary>
        /// Adds <see cref="IScheduledJob"/> to DI with options.
        /// </summary>
        /// <typeparam name="TJob">The type of the job.</typeparam>
        /// <typeparam name="TJobOptions">The options for the job.</typeparam>
        /// <param name="configure"></param>
        /// <param name="sectionName"></param>
        /// <param name="jobName">The name of the job, use this for options as well.</param>
        /// <returns></returns>
        public IServiceCollection AddJob<TJob, TJobOptions>(
                Action<TJobOptions>? configure = default,
                string sectionName = "SchedulerJobs",
                string? jobName = null)
                where TJob : class, IScheduledJob
                where TJobOptions : SchedulerOptions, new()
        {
            Services.AddSingleton<IScheduledJob, TJob>();

            var name = jobName ?? typeof(TJob).Name;

            AddOptions(configure, sectionName, name);

            return Services;
        }

        /// <summary>
        /// Adds options for the custom job.
        /// </summary>
        /// <typeparam name="TJob"></typeparam>
        /// <param name="sectionName"></param>
        /// <param name="configure"></param>
        /// <returns></returns>
        public IServiceCollection AddJobOptions<TJob>(
            string sectionName = "SchedulerJobs",
            string? jobName = default,
            Action<SchedulerOptions>? configure = null)
             where TJob : class, IScheduledJob
        {
            var name = jobName ?? typeof(TJob).Name;

            Services
              .AddChangeTokenOptions<SchedulerOptions>(
              $"{sectionName}:{name}",
              name,
              o =>
              {
                  configure?.Invoke(o);
                  o.JobName = name;
              });

            return Services;
        }

        /// <summary>
        /// Add Jobs options based on the string name.
        /// </summary>
        /// <param name="namedJob">The named job.</param>
        /// <param name="sectionName">The section name.</param>
        /// <param name="configure">The custom options configuration.</param>
        /// <returns></returns>
        public IServiceCollection AddJobOptions(
            string namedJob,
            string sectionName,
            Action<SchedulerOptions>? configure = null)
        {
            return Services.AddChangeTokenOptions(sectionName, namedJob, configure);
        }

        private void AddOptions<TJobOptions>(
            Action<TJobOptions>? configure,
            string sectionName,
            string name) where TJobOptions : SchedulerOptions, new()
        {
            // named options used within the job.
            Services
                .AddChangeTokenOptions<TJobOptions>(
                $"{sectionName}:{name}",
                name,
                o =>
                {
                    configure?.Invoke(o);
                    o.JobName = name;
                });

            var so = new Action<SchedulerOptions, IServiceProvider>(
                    (o, sp) =>
                    {
                        var options = sp.GetRequiredService<IOptionsMonitor<TJobOptions>>().Get(name);

                        o.CronSchedule = options.CronSchedule;
                        o.CronTimeZone = options.CronTimeZone;
                        o.RunImmediately = options.RunImmediately;
                        o.JobName = options.JobName;
                    });

            Services
                .AddChangeTokenOptions($"{sectionName}:{name}", name, so);
        }
    }
}
