using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;

using CronScheduler.Extensions.BackgroundTask;
using CronScheduler.Extensions.Scheduler;
using CronSchedulerApp.Jobs;
using CronSchedulerApp.Models;
using CronSchedulerApp.Services;

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace CronSchedulerApp.Controllers
{
    public class HomeController : Controller
    {
        private readonly IBackgroundTaskQueue _taskQueue;
        private readonly ILogger<HomeController> _logger;
        private readonly TorahVerses _torahVerses;
        private readonly ISchedulerRegistration _schedulerRegistration;
        private readonly ILoggerFactory _loggerFactory;

        public HomeController(
            IBackgroundTaskQueue taskQueue,
            ILogger<HomeController> logger,
            ILoggerFactory loggerFactory,
            ISchedulerRegistration schedulerRegistration,
            TorahVerses torahVerses)
        {
            _taskQueue = taskQueue;
            _logger = logger;
            _torahVerses = torahVerses;
            _schedulerRegistration = schedulerRegistration;
            _loggerFactory = loggerFactory;
        }

        public IActionResult Index()
        {
            var jobOptions = new SchedulerOptions
            {
                CronSchedule = "0/1 * * * * *",
                RunImmediately = true
            };

            _schedulerRegistration.AddOrUpdate(new TestJob(jobOptions, _loggerFactory.CreateLogger<TestJob>()), jobOptions);

            if (_torahVerses.Current != null)
            {
                var text = _torahVerses.Current.Select(x => x.Text).Aggregate((i, j) => i + Environment.NewLine + j);
                var bookName = _torahVerses.Current.Select(x => x.Bookname).Distinct().FirstOrDefault();
                var chapter = _torahVerses.Current.Select(x => x.Chapter).Distinct().FirstOrDefault();
                var versesArray = _torahVerses.Current.Select(x => x.Verse).Aggregate((i, j) => $"{i};{j}").Split(';');

                var verses = string.Empty;

                if (versesArray.Length > 1)
                {
                    verses = $"{versesArray.FirstOrDefault()}-{versesArray.Reverse().FirstOrDefault()}";
                }
                else
                {
                    verses = versesArray.FirstOrDefault();
                }

                ViewBag.Text = text;
                ViewBag.BookName = bookName;
                ViewBag.Chapter = chapter;
                ViewBag.Verses = verses;
                ViewBag.Url = $"https://studybible.info/KJV_Strongs/{Uri.EscapeDataString($"{bookName} {chapter}:{verses}")}";
            }

            return View();
        }

        public IActionResult About()
        {
            ViewData["Message"] = "Your application description page.";

            return View();
        }

        public IActionResult Contact()
        {
            ViewData["Message"] = "Your contact page.";

            return View();
        }

        public IActionResult Privacy()
        {
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }

        public IActionResult Queue()
        {
            ViewData["Message"] = "Background Queue Hosted Service Test";
            var processId = $" Queued-Task-{Guid.NewGuid().ToString()} ";

            ViewData["Process"] = processId;

            _taskQueue.QueueBackgroundWorkItem(
                async (token) =>
                {
                    token.Register(() =>
                    {
                        _logger.LogInformation("{Task}  canceled.", processId);
                    });

                    token.ThrowIfCancellationRequested();

                    var guid = Guid.NewGuid().ToString();

                    var repeat = 4;
                    var idx = 0;

                    for (var delayLoop = 0; delayLoop < repeat; delayLoop++)
                    {
                        ++idx;

                        // if (idx == new Random().Next(0, repeat))
                        // {
                        //    throw new AggregateException("Something went wrong");
                        // }
                        _logger.LogInformation($"Queued Background Task {guid} is running. {delayLoop}/{idx}");
                        await Task.Delay(TimeSpan.FromSeconds(10), token);
                    }

                    _logger.LogInformation($"Queued Background Task {guid} is complete. {repeat}/{idx}");
                },
                processId,
                ex =>
                {
                    _logger.LogError(ex.ToString());
                });

            return View();
        }
    }
}
