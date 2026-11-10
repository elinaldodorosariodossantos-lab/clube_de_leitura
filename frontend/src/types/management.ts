import type {AdminStudent} from './admin';
export type ManagedStudent=AdminStudent&{birthDate:string|null;guardian:string|null;schoolYear?:number};
export type AccessCard={student:ManagedStudent;needsCredentials?:boolean;code?:string;link?:string;qr?:string;schoolYear?:number};
export type ManagedStudents={students:ManagedStudent[];total:number;schools:{id:string;name:string}[];classes:string[]};
export type StoryQuestion={prompt:string;options:string[];correct:number;value?:number|null};
export type BookPage={layout?:'illustration'|'side'|'frame';id:string;text:string;image:string};
export type Story={pages?:BookPage[];pagesProtected?:boolean;confirmPageRemoval?:boolean;id?:string;title:string;author:string;level:'facil'|'medio'|'dificil';age:string;cover:string;active:boolean;required:boolean;ordering:number;content:string;summary:string;minutes:number|null;questions:StoryQuestion[]};
export type StoryRow=Omit<Story,'questions'>&{id:string;questions:number};
