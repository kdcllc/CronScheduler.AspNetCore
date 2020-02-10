using System;
using System.Collections.Generic;

namespace CronSchedulerApp.Services
{
    public class TorahVerses
    {
        public IList<TorahVerses> Current { get; set; } = new List<TorahVerses>();

        public string Bookname { get; set; } = string.Empty;

        public string Chapter { get; set; } = string.Empty;

        public string Verse { get; set; } = string.Empty;

        public string Text { get; set; } = string.Empty;

        public string Title { get; set; } = string.Empty;

        public string[] Titles { get; set; } = Array.Empty<string>();
    }
}
