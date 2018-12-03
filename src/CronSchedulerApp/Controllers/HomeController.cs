using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using CronSchedulerApp.Models;
using CronSchedulerApp.Services;

namespace CronSchedulerApp.Controllers
{
    public class HomeController : Controller
    {
        private readonly TorahSettings _options;

        public HomeController(IOptions<TorahSettings> options)
        {
            _options = options.Value;
        }

        public IActionResult Index()
        {

            var text = TorahVerses.Current.Select(x => x.Text).Aggregate((i,j)=> i + Environment.NewLine + j);
            var bookName = TorahVerses.Current.Select(x => x.Bookname).Distinct().FirstOrDefault();
            var chapter = TorahVerses.Current.Select(x => x.Chapter).Distinct().FirstOrDefault();
            var versesArray = TorahVerses.Current.Select(x => x.Verse).Aggregate((i, j) => $"{i};{j}").Split(';');

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
    }
}
